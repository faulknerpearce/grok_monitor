import Foundation
import Combine
import os
import Security
import WebKit

/// Persists grok.com session cookies and optional bearer token under Application Support.
/// Keychain is intentionally avoided — ad-hoc/debug builds spam "wants to access keychain" dialogs in a loop.
@MainActor
final class AuthSessionService: ObservableObject {
    static let shared = AuthSessionService()

    private let logger = Logger(subsystem: "com.grokusage.app", category: "Auth")

    /// Cookie names that indicate a real authenticated session (not anonymous browsing).
    private static let authCookieHints: Set<String> = [
        "sso", "session", "auth", "token", "jwt", "sid", "user", "account",
        "x-session", "xai", "oidc", "refresh", "access"
    ]

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var accountEmail: String?
    /// True when credentials are missing or the last refresh received 401/403.
    @Published var needsSignIn: Bool = false
    @Published private(set) var lastAuthError: String?

    private init() {
        KeychainCleanup.deleteLegacyItems()
        refreshFromDisk()
    }

    /// Call when the usage API returns 401/403 so the UI can prompt re-auth.
    func markSessionInvalid(reason: String? = nil) {
        needsSignIn = true
        if let reason {
            lastAuthError = reason
        }
        removeStore(key: "session")
        removeStore(key: "token")
        removeStore(key: "email")
        logger.info("Session marked invalid, on-disk auth cleared")
    }

    func refreshFromDisk() {
        let cookies = loadCookieHeader()
        isSignedIn = !(cookies?.isEmpty ?? true) || loadBearerToken() != nil
        accountEmail = loadAccountEmail()
        needsSignIn = !isSignedIn
        if let cookies, !cookies.isEmpty {
            applyCookiesToHTTPCookieStorage(cookies)
        }
    }

    /// Captures authenticated cookies from the shared WKWebsiteDataStore.
    func captureCookiesFromWebKit() async -> Bool {
        let cookies = await WKWebsiteDataStoreBridge.shared.allCookies()
        let relevant = cookies.filter { isRelevantDomain($0.domain) }
        let authCookies = relevant.filter { looksLikeAuthCookie($0) }

        logger.info(
            "Cookie capture: total=\(cookies.count, privacy: .public) relevant=\(relevant.count, privacy: .public) auth=\(authCookies.count, privacy: .public)"
        )

        let chosen: [HTTPCookie]
        if !authCookies.isEmpty {
            chosen = relevant
        } else if relevant.count >= 2 {
            chosen = relevant
        } else {
            lastAuthError = "No session cookies found. Finish signing in, then click Capture Session."
            logger.warning("No auth cookies found after sign-in")
            return false
        }

        let header = chosen
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        save(cookieHeader: header)

        let storage = HTTPCookieStorage.shared
        for cookie in chosen {
            storage.setCookie(cookie)
        }

        if let email = extractEmail(from: chosen) {
            save(accountEmail: email)
        }

        isSignedIn = true
        needsSignIn = false
        lastAuthError = nil
        logger.info("Captured \(chosen.count, privacy: .public) session cookies")
        return true
    }

    func save(cookieHeader: String) {
        writeStore(key: "session", value: cookieHeader)
        isSignedIn = true
        needsSignIn = false
    }

    func save(accountEmail: String) {
        writeStore(key: "email", value: accountEmail)
        self.accountEmail = accountEmail
    }

    func save(bearerToken: String) {
        writeStore(key: "token", value: bearerToken)
        isSignedIn = true
        needsSignIn = false
    }

    func loadCookieHeader() -> String? {
        readStore(key: "session")
    }

    func loadBearerToken() -> String? {
        readStore(key: "token")
    }

    func loadAccountEmail() -> String? {
        readStore(key: "email")
    }

    func signOut() {
        removeStore(key: "session")
        removeStore(key: "token")
        removeStore(key: "email")
        let storage = HTTPCookieStorage.shared
        for domain in ["grok.com", "x.ai", "x.com"] {
            if let url = URL(string: "https://\(domain)") {
                storage.cookies(for: url)?.forEach { storage.deleteCookie($0) }
            }
        }
        Task {
            await WKWebsiteDataStoreBridge.shared.clearCookies()
        }
        isSignedIn = false
        accountEmail = nil
        needsSignIn = true
        lastAuthError = nil
        logger.info("Signed out")
    }

    // MARK: - Helpers

    private func isRelevantDomain(_ domain: String) -> Bool {
        let d = domain.lowercased()
        return d.contains("grok.com")
            || d.contains("x.ai")
            || d.contains("x.com")
            || d.contains("twitter.com")
    }

    private func looksLikeAuthCookie(_ cookie: HTTPCookie) -> Bool {
        let name = cookie.name.lowercased()
        guard Self.authCookieHints.contains(where: { name.contains($0) }) else { return false }
        return cookie.isSecure || cookie.isHTTPOnly
    }

    private func extractEmail(from cookies: [HTTPCookie]) -> String? {
        for cookie in cookies where ["email", "user_email"].contains(cookie.name.lowercased()) {
            let decoded = cookie.value.removingPercentEncoding ?? cookie.value
            if decoded.contains("@") && decoded.contains(".") {
                return decoded
            }
        }
        return nil
    }

    private func applyCookiesToHTTPCookieStorage(_ header: String) {
        // UsageClient sends Cookie explicitly; also seed shared storage for completeness.
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if let cookie = HTTPCookie(properties: [
                .name: kv[0],
                .value: kv[1],
                .domain: ".grok.com",
                .path: "/"
            ]) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    // MARK: - Application Support store (no Keychain)

    private var storeDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GrokUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Restrict directory to the current user (0600 files below).
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dir.path
        )
        return dir
    }

    private func storeURL(key: String) -> URL {
        storeDir.appendingPathComponent("auth_\(key).dat")
    }

    private func writeStore(key: String, value: String) {
        let url = storeURL(key: key)
        try? Data(value.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func readStore(key: String) -> String? {
        guard let data = try? Data(contentsOf: storeURL(key: key)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func removeStore(key: String) {
        try? FileManager.default.removeItem(at: storeURL(key: key))
    }
}

/// Deletes legacy Keychain entries from earlier builds that cause access-dialog loops.
enum KeychainCleanup {
    static func deleteLegacyItems() {
        let services = [
            "com.grokusage.app.cookies",
            "com.grokusage.app.account",
            "com.grokusage.app.bearer"
        ]
        let accounts = ["session", "email", "token"]
        for service in services {
            for account in accounts {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                // Delete without reading — reading is what triggers the password prompt loop.
                SecItemDelete(query as CFDictionary)
            }
        }
    }
}

/// Thin async bridge over `WKWebsiteDataStore.httpCookieStore`.
enum WKWebsiteDataStoreBridge {
    static let shared = WKWebsiteDataStoreBridgeImpl()
}

final class WKWebsiteDataStoreBridgeImpl {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func clearCookies() async {
        let cookies = await allCookies()
        let relevant = cookies.filter { cookie in
            let d = cookie.domain.lowercased()
            return d.contains("grok.com") || d.contains("x.ai") || d.contains("x.com")
        }
        for cookie in relevant {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }
}
