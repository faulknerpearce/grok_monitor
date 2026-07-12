import SwiftUI
import AppKit
import Combine

@main
struct GrokMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot(model: model)
        } label: {
            MenuBarLabelContainer(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Grok Monitor", id: "preferences") {
            PreferencesRoot(model: model)
        }
        .defaultSize(width: 480, height: 640)

        Window("Usage History", id: "charts") {
            HistoryChartView(history: model.history)
        }
        .defaultSize(width: 640, height: 480)

        Window("Sign in to Grok", id: "signin") {
            SignInView(auth: model.auth) {
                Task { await model.poller.refreshNow() }
                AppDelegate.hideDockIfNoWindows()
            }
            .background(Color.clear
                .frame(width: 0, height: 0)
                .onDisappear {
                    AppDelegate.hideDockIfNoWindows()
                }
            )
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)
    }
}

/// Shared app services owned for the process lifetime.
@MainActor
final class AppModel: ObservableObject {
    let auth = AuthSessionService.shared
    let settings = AppSettings()
    let history = HistoryStore()
    let notifier = ThresholdNotifier()
    let poller: UsagePoller

    private var cancellables = Set<AnyCancellable>()

    init() {
        poller = UsagePoller(
            auth: AuthSessionService.shared,
            history: history,
            settings: settings,
            notifier: notifier
        )
        forwardChanges(from: settings)
        forwardChanges(from: poller)
        forwardChanges(from: auth)
        forwardChanges(from: history)
        notifier.requestAuthorizationIfNeeded()
        poller.start()
    }

    /// MenuBarExtra label only observes `AppModel`; forward child updates.
    private func forwardChanges(from object: some ObservableObject) {
        object.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

struct MenuBarRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarPanelView(
            auth: model.auth,
            poller: model.poller,
            settings: model.settings,
            history: model.history,
            openPreferences: {
                AppDelegate.revealWindow()
                openWindow(id: "preferences")
            },
            openCharts: {
                AppDelegate.revealWindow()
                openWindow(id: "charts")
            },
            openSignIn: {
                AppDelegate.revealWindow()
                openWindow(id: "signin")
            }
        )
    }
}

private struct PreferencesRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PreferencesView(
            auth: model.auth,
            settings: model.settings,
            history: model.history,
            poller: model.poller,
            openSignIn: {
                AppDelegate.revealWindow()
                openWindow(id: "signin")
            }
        )
    }
}

/// Observes nested services so the menu bar label refreshes on poll/settings updates.
struct MenuBarLabelContainer: View {
    @ObservedObject var model: AppModel

    var body: some View {
        MenuBarLabelView(
            snapshot: model.poller.snapshot,
            isSignedIn: model.auth.isSignedIn && !model.auth.needsSignIn,
            showBar: model.settings.showBarGraphInMenuBar,
            showCategories: model.settings.showCategoriesInMenuBar,
            visibleProductIDs: model.settings.visibleProductIDs
        )
    }
}
