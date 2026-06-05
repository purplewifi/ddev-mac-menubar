import AppKit

enum AppActivation {
    static func showLogWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func restoreMenuBarOnlyIfNeeded() {
        DispatchQueue.main.async {
            let hasVisibleAppWindows = NSApp.windows.contains { window in
                window.isVisible && !window.isKind(of: NSPanel.self)
            }
            guard !hasVisibleAppWindows else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
