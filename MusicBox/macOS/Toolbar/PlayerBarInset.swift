#if os(macOS)
import AppKit

extension NSScrollView {
    /// Reserves the docked player bar's height at the bottom of this scroll view.
    ///
    /// The bar is drawn by a window-level overlay rather than taking layout space in the
    /// detail column — inside `detail:` it doesn't lay out at all — so nothing insets
    /// these scroll views automatically. SwiftUI's `.safeAreaInset` doesn't reach an
    /// AppKit scroll view inside a representable either: without this, lists run under
    /// the bar and their last rows can't be scrolled into view. contentInsets also moves
    /// the scroller up, which is what stops the bar covering it.
    func reserveSpaceForPlayerBar() {
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: PlayerBottomBar.height, right: 0)
    }
}
#endif
