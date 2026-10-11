#if os(macOS)
import AppKit
import Foundation

/// Routes "show me this in the library" requests, which can arrive while the library
/// window isn't there to receive them.
///
/// `MacOSContentView` unmounts when its window closes, taking its notification handlers
/// with it — so a Go to Album from the mini player, or Go to Current Song from the menu
/// bar, posted into nothing. Requests made with no main window are held, the window is
/// opened, and the request is delivered once the view is back.
@MainActor
enum MainWindowNavigation {
    private static var pending: (name: Notification.Name, object: Any?)?

    static func request(_ name: Notification.Name, object: Any? = nil) {
        guard isMainWindowVisible else {
            pending = (name, object)
            openMainWindow()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: name, object: object)
    }

    /// Called by MacOSContentView once its handlers are installed.
    static func deliverPending() {
        guard let request = pending else { return }
        pending = nil
        NotificationCenter.default.post(name: request.name, object: request.object)
    }

    private static var isMainWindowVisible: Bool {
        NSApp.windows.contains { MacOSAppDelegate.isMainWindow($0) && $0.isVisible }
    }

    private static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: MacOSAppDelegate.isMainWindow) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // The scene's window is gone entirely, so it has to come back through SwiftUI's
        // own openWindow — which the Window menu's item is already wired to. Matched on
        // its key equivalent rather than its title, which is localized.
        guard let menu = NSApp.mainMenu?.item(withTitle: "Window")?.submenu,
            let index = menu.items.firstIndex(where: {
                $0.keyEquivalent == "0" && $0.keyEquivalentModifierMask == .command
            })
        else { return }
        menu.performActionForItem(at: index)
    }
}
#endif
