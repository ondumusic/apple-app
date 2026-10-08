#if os(macOS)
import AppKit
import SwiftUI

/// Corner radii for chrome we draw ourselves that has to sit against AppKit's.
///
/// AppKit exposes no way to ask a control for its bezel radius — `NSBox.cornerRadius`
/// and `NSGlassEffectView.cornerRadius` are settable, not readable, and nothing on
/// `NSTextField` or `NSTableView` reports the shape they draw. So these are matched by
/// eye, per OS, in one place rather than scattered as literals.
///
/// macOS 26 ("Tahoe") rounded controls substantially and macOS 27 walked some of that
/// back, so a matched-by-eye number needs redoing every release. This is the last one,
/// and it survives because NSTableView's selection is ours to draw either way.
enum SystemChrome {

    /// A source-list row's selection pill.
    static func selectionCornerRadius(height: CGFloat) -> CGFloat {
        if #available(macOS 26, *) { return min(height / 2, 10) }
        return 6
    }
}

extension View {
    /// The surface pages sit on. From macOS 26 that's the window's own material; the
    /// NSColor backgrounds are a flat fill darker than it, which Music doesn't use.
    /// Before 26 the window material is a lighter grey than Music's pages, which sit
    /// on the content colour.
    @ViewBuilder
    func pageBackground() -> some View {
        if #available(macOS 26, *) {
            background(.windowBackground)
        } else {
            background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
#endif
