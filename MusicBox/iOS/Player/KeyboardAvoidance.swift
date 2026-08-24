import SwiftUI

#if os(iOS)
import UIKit

/// Replaces SwiftUI's automatic keyboard avoidance for the tab content, which
/// can leave its inset applied after the keyboard dismisses mid-transition
/// (navigation push from search results, tab switch). Views opt out with
/// `.ignoresSafeArea(.keyboard)` and pad by `KeyboardAvoidance.overlap`
/// instead, driven directly by UIKit's keyboard notifications.
@Observable
final class KeyboardObserver {
    static let shared = KeyboardObserver()

    /// Keyboard end frame in screen coordinates; nil while the keyboard is hidden.
    private(set) var keyboardFrame: CGRect?
    private(set) var animationDuration: Double = 0.25

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        updateDuration(from: note)
        keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        updateDuration(from: note)
        keyboardFrame = nil
    }

    private func updateDuration(from note: Notification) {
        if let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double, duration > 0 {
            animationDuration = duration
        }
    }
}

nonisolated enum KeyboardAvoidance {
    /// Bottom padding needed for `contentFrame` (window coordinates) to clear a
    /// keyboard at `keyboardFrame` (screen coordinates). A floating iPad
    /// keyboard is narrower than the content and gets no inset, matching
    /// UIKit's own convention. An off-screen end frame (keyboard sliding out)
    /// yields zero because its minY is at or below the content's maxY.
    static func overlap(contentFrame: CGRect, keyboardFrame: CGRect?) -> CGFloat {
        guard let keyboardFrame, keyboardFrame.width >= contentFrame.width else { return 0 }
        return max(0, contentFrame.maxY - keyboardFrame.minY)
    }
}
#endif
