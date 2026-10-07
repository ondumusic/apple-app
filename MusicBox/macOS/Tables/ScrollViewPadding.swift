#if os(macOS)
import AppKit

extension NSScrollView {
    /// A little room under the last row.
    ///
    /// Without it the final row sits flush against the window's bottom edge, which is
    /// most obvious when it's selected — the accent pill runs into the edge with nothing
    /// under it.
    func addBottomContentPadding(_ amount: CGFloat = 10) {
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: contentInsets.top, left: 0, bottom: amount, right: 0)
    }

    /// Room above the first row for chrome floating over the top of the scroll view, so
    /// content starts clear of it and scrolls underneath.
    func setTopContentInset(_ amount: CGFloat) {
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: amount, left: 0, bottom: contentInsets.bottom, right: 0)
    }
}
#endif
