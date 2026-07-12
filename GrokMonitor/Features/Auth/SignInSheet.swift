import SwiftUI
import WebKit
import AppKit

struct SignInView: View {
    @ObservedObject var auth: AuthSessionService
    var onComplete: () -> Void

    @State private var statusMessage =
        "Sign in with your Grok / xAI account below. When you land back on grok.com, click Capture Session."
    @State private var isCapturing = false
    @State private var sawAuthHost = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Grok")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let err = auth.lastAuthError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            SignInWebView(
                onAuthHostSeen: {
                    sawAuthHost = true
                    statusMessage = "Complete sign-in in the page. When you return to grok.com, click Capture Session."
                },
                onReturnedToGrok: {
                    guard sawAuthHost else { return }
                    statusMessage = "Back on grok.com — capturing session…"
                    Task { await capture() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button("I'm signed in — Capture Session") {
                    Task { await capture() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCapturing)

                Spacer()

                Button("Done") {
                    onComplete()
                    dismiss()
                }
            }
            .padding()
        }
        .frame(minWidth: 880, minHeight: 640)
        .onAppear {
            NSApp.activate()
        }
    }

    private func capture() async {
        isCapturing = true
        defer { isCapturing = false }
        let ok = await auth.captureCookiesFromWebKit()
        if ok {
            statusMessage = "Session captured."
            onComplete()
            dismiss()
        } else {
            statusMessage = auth.lastAuthError
                ?? "No session cookies found yet. Finish signing in, then click Capture Session."
        }
    }
}

struct SignInWebView: NSViewRepresentable {
    var onAuthHostSeen: () -> Void
    var onReturnedToGrok: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthHostSeen: onAuthHostSeen, onReturnedToGrok: onReturnedToGrok)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Start at accounts so users don't get anonymous grok.com cookies first.
        webView.load(URLRequest(url: URL(string: "https://accounts.x.ai/sign-in?redirect=https%3A%2F%2Fgrok.com%2F%3F_s%3Dusage")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onAuthHostSeen = onAuthHostSeen
        context.coordinator.onReturnedToGrok = onReturnedToGrok
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onAuthHostSeen: () -> Void
        var onReturnedToGrok: () -> Void
        private var sawAuthHost = false
        private var didAutoCapture = false

        init(onAuthHostSeen: @escaping () -> Void, onReturnedToGrok: @escaping () -> Void) {
            self.onAuthHostSeen = onAuthHostSeen
            self.onReturnedToGrok = onReturnedToGrok
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let host = webView.url?.host?.lowercased() else { return }

            if host.contains("accounts.x.ai")
                || host.contains("auth.x.ai")
                || host.contains("api.x.com")
                || host.contains("twitter.com")
                || host.contains("x.com")
            {
                if !sawAuthHost {
                    sawAuthHost = true
                    onAuthHostSeen()
                }
                return
            }

            if host.contains("grok.com"), sawAuthHost, !didAutoCapture {
                didAutoCapture = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.onReturnedToGrok()
                }
            }
        }

        // Allow OAuth popups / new windows inside the same web view.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
