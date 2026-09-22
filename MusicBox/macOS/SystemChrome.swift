#if os(macOS)
import AppKit

/// Corner radii for chrome we draw ourselves that has to sit against AppKit's.
///
/// AppKit exposes no way to ask a control for its bezel radius — `NSBox.cornerRadius`
/// and `NSGlassEffectView.cornerRadius` are settable, not readable, and nothing on
/// `NSTextField` or `NSTableView` reports the shape they draw. So these are matched by
/// eye, per OS, in one place rather than scattered as literals.
///
/// macOS 26 ("Tahoe") rounded controls substantially. Before it, a search field bezel
/// and a source-list selection were both 6pt rounded rects, which is why 6 was hardcoded
/// in two places and looked right until it didn't.
enum SystemChrome {

    /// A text or search field's bezel. Pill-shaped from 26 on.
    static func fieldCornerRadius(height: CGFloat) -> CGFloat {
        if #available(macOS 26, *) { return height / 2 }
        return 6
    }

    /// A source-list row's selection pill.
    static func selectionCornerRadius(height: CGFloat) -> CGFloat {
        if #available(macOS 26, *) { return min(height / 2, 10) }
        return 6
    }
}
#endif
