import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var showCategoriesInMenuBar: Bool {
        didSet {
            guard showCategoriesInMenuBar != oldValue else { return }
            defaults.set(showCategoriesInMenuBar, forKey: Keys.showCategories)
        }
    }

    @Published var showBarGraphInMenuBar: Bool {
        didSet {
            guard showBarGraphInMenuBar != oldValue else { return }
            defaults.set(showBarGraphInMenuBar, forKey: Keys.showBar)
        }
    }

    @Published var activePollSeconds: Int {
        didSet {
            let clamped = Self.clampActivePoll(activePollSeconds)
            if activePollSeconds != clamped { activePollSeconds = clamped }
            defaults.set(activePollSeconds, forKey: Keys.activePoll)
        }
    }

    @Published var idlePollSeconds: Int {
        didSet {
            let clamped = Self.clampIdlePoll(idlePollSeconds)
            if idlePollSeconds != clamped { idlePollSeconds = clamped }
            defaults.set(idlePollSeconds, forKey: Keys.idlePoll)
        }
    }

    @Published var thresholdEnabled: Bool {
        didSet { defaults.set(thresholdEnabled, forKey: Keys.thresholdEnabled) }
    }

    @Published var thresholdPercent: Double {
        didSet { defaults.set(thresholdPercent, forKey: Keys.thresholdPercent) }
    }

    @Published var visibleProductIDs: Set<String> {
        didSet {
            defaults.set(Array(visibleProductIDs), forKey: Keys.visibleProducts)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin, launchAtLogin != oldValue else { return }
            updateLaunchAtLogin()
        }
    }

    /// Guards against recursive `didSet` when registration fails and we revert.
    private var isRevertingLaunchAtLogin = false

    init() {
        showCategoriesInMenuBar = defaults.object(forKey: Keys.showCategories) as? Bool ?? true
        showBarGraphInMenuBar = defaults.object(forKey: Keys.showBar) as? Bool ?? true
        // Clamp on load — didSet does not run during init.
        activePollSeconds = Self.clampActivePoll(defaults.object(forKey: Keys.activePoll) as? Int ?? 60)
        idlePollSeconds = Self.clampIdlePoll(defaults.object(forKey: Keys.idlePoll) as? Int ?? 300)
        thresholdEnabled = defaults.object(forKey: Keys.thresholdEnabled) as? Bool ?? true
        thresholdPercent = defaults.object(forKey: Keys.thresholdPercent) as? Double ?? 80
        let products = defaults.stringArray(forKey: Keys.visibleProducts)
            ?? ProductCatalog.knownIDs
        visibleProductIDs = Set(products)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func clampActivePoll(_ value: Int) -> Int { max(15, min(300, value)) }
    private static func clampIdlePoll(_ value: Int) -> Int { max(15, min(3600, value)) }

    func filteredProducts(from snapshot: WeeklyUsageSnapshot) -> [ProductUsage] {
        ProductCatalog.sortForDisplay(
            snapshot.products.filter {
                visibleProductIDs.contains($0.id.lowercased()) && $0.percentOfPool > 0.05
            }
        )
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert UI if registration fails (e.g. unsigned debug builds).
            let actual = SMAppService.mainApp.status == .enabled
            guard launchAtLogin != actual else { return }
            isRevertingLaunchAtLogin = true
            launchAtLogin = actual
            isRevertingLaunchAtLogin = false
        }
    }

    private enum Keys {
        static let showCategories = "showCategoriesInMenuBar"
        static let showBar = "showBarGraphInMenuBar"
        static let activePoll = "activePollSeconds"
        static let idlePoll = "idlePollSeconds"
        static let thresholdEnabled = "thresholdEnabled"
        static let thresholdPercent = "thresholdPercent"
        static let visibleProducts = "visibleProductIDs"
    }
}
