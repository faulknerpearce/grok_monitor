import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent-style menu bar app: hide Dock icon (also LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Bring the app forward so windows from a menu-bar-only agent are visible.
    static func revealWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hideDockIfNoWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let visible = NSApp.windows.contains {
                $0.isVisible && !$0.className.contains("StatusBar") && $0.canBecomeKey
            }
            if !visible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}


