#if os(iOS)
import SwiftUI

/// The Home Screen icon's long-press menu. Start only: ending is done from the strip
/// inside the app, and launching the app to stop something reads backwards.
enum PrivateSessionQuickAction {
    static let type = "startPrivateSession"

    static func refresh(from settings: SettingsStore) {
        guard settings.recordPlays, !settings.isPrivateSession else {
            UIApplication.shared.shortcutItems = []
            return
        }
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: type,
                localizedTitle: String(localized: "Start Private Session"),
                localizedSubtitle: String(localized: "Plays aren't counted"),
                icon: UIApplicationShortcutIcon(systemImageName: "eye.slash"))
        ]
    }

    /// Returns whether the item was ours.
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == type else { return false }
        SettingsStore.shared.startPrivateSession()
        return true
    }
}

/// SwiftUI keeps hosting the window; this only exists because a quick action arrives
/// through the scene delegate and nowhere else.
final class QuickActionSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let item = options.shortcutItem {
            PrivateSessionQuickAction.handle(item)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor item: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(PrivateSessionQuickAction.handle(item))
    }
}
#endif
