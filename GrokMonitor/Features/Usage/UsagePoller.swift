import Foundation
import Combine
import os
import AppKit

/// Periodically refreshes usage and publishes the latest snapshot.
@MainActor
final class UsagePoller: ObservableObject {
    @Published private(set) var snapshot: WeeklyUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshedAt: Date?
    @Published var menuIsOpen = false

    private let auth: AuthSessionService
    private let history: HistoryStore
    private let settings: AppSettings
    private let notifier: ThresholdNotifier
    private let logger = Logger(subsystem: "com.grokmonitor.app", category: "Poller")

    private var timerTask: Task<Void, Never>?
    private var backoffSeconds: TimeInterval = 0
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var pausedForSleep = false

    init(
        auth: AuthSessionService = .shared,
        history: HistoryStore,
        settings: AppSettings,
        notifier: ThresholdNotifier
    ) {
        self.auth = auth
        self.history = history
        self.settings = settings
        self.notifier = notifier
        observeSleep()
    }

    deinit {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    func start() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            await self?.refreshNow()
            while let self, !Task.isCancelled {
                let interval = self.currentInterval() + self.backoffSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                if self.pausedForSleep { continue }
                await self.refreshNow()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    func clearSnapshot() {
        snapshot = nil
        lastError = nil
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // needsSignIn means credentials were cleared after 401/403 — wait for re-auth
        // instead of spinning on empty cookies every poll interval.
        guard auth.isSignedIn, !auth.needsSignIn else {
            lastError = UsageClientError.notSignedIn.localizedDescription
            if !auth.isSignedIn {
                auth.markSessionInvalid()
            }
            return
        }

        let client = UsageClient(
            cookieHeader: auth.loadCookieHeader(),
            bearerToken: auth.loadBearerToken(),
            accountEmail: auth.accountEmail
        )

        do {
            var snap = try await client.fetchUsage()
            if snap.accountEmail == nil {
                snap.accountEmail = auth.accountEmail
            }
            snapshot = snap
            lastError = nil
            lastRefreshedAt = Date()
            backoffSeconds = 0
            auth.needsSignIn = false
            history.append(snap)
            notifier.evaluate(usedPercent: snap.usedPercent, settings: settings)
            logger.info("Usage refreshed: \(snap.usedPercent, format: .fixed(precision: 1))% used")
        } catch let error as UsageClientError {
            lastError = error.localizedDescription
            if error == .unauthorized || error == .notSignedIn {
                auth.markSessionInvalid(reason: error.localizedDescription)
            }
            applyBackoff()
            logger.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            applyBackoff()
            logger.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func currentInterval() -> TimeInterval {
        if menuIsOpen {
            return TimeInterval(settings.activePollSeconds)
        }
        return TimeInterval(settings.idlePollSeconds)
    }

    private func applyBackoff() {
        if backoffSeconds == 0 {
            backoffSeconds = 30
        } else {
            backoffSeconds = min(backoffSeconds * 2, 600)
        }
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pausedForSleep = true }
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pausedForSleep = false
                await self?.refreshNow()
            }
        }
    }
}
