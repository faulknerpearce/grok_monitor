import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let dockHideGracePeriod: TimeInterval = 0.25

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    static func revealWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func hideDockIfNoWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + dockHideGracePeriod) {
            let visible = NSApp.windows.contains {
                $0.isVisible && !$0.styleMask.contains(.nonactivatingPanel) && $0.canBecomeKey
            }
            if !visible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}


