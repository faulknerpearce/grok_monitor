import Foundation
import Combine
import UserNotifications
import os

@MainActor
final class ThresholdNotifier: ObservableObject {
    private let logger = Logger(subsystem: "com.grokusage.app", category: "Alerts")
    private var lastNotifiedThreshold: Double?

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                Task { @MainActor in
                    if let error {
                        self?.logger.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
                    }
                    if !granted {
                        self?.logger.info("User denied notification permission")
                    }
                }
            }
        }
    }

    func evaluate(usedPercent: Double, settings: AppSettings) {
        guard settings.thresholdEnabled else { return }
        let threshold = settings.thresholdPercent
        guard usedPercent >= threshold else {
            if let last = lastNotifiedThreshold, usedPercent < last - 5 {
                lastNotifiedThreshold = nil
            }
            return
        }
        if let last = lastNotifiedThreshold, last >= threshold {
            return
        }
        lastNotifiedThreshold = threshold
        send(usedPercent: usedPercent, threshold: threshold)
    }

    private func send(usedPercent: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Grok Usage Alert"
        content.body = String(
            format: "Weekly SuperGrok usage is at %.0f%% (threshold %.0f%%).",
            usedPercent,
            threshold
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "grok-usage-threshold-\(Int(threshold))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("Sent threshold notification at \(usedPercent, privacy: .public)%")
    }
}
