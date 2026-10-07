#if os(macOS)
import SwiftUI

extension EnvironmentValues {
    /// How much window chrome — the player row, and any server notices under it —
    /// floats over the top of the detail column.
    @Entry var floatingChromeHeight: CGFloat = 0
    /// How far down a page's content starts: the floating chrome plus the page's own
    /// header. For views nested inside a ChromedPage's content; the content closure
    /// itself is handed the same value, since it's built outside the page's environment.
    @Entry var pageTopInset: CGFloat = 0
    @Entry var contentHeaderFloats = false
}

/// A page laid out under the window's floating chrome, with an optional header.
///
/// From macOS 26 the chrome and the header float over the content on one translucent
/// surface, and the content scrolls underneath. Before 26 there's no glass for it to
/// blur through, so the header sits above the content as it always did.
struct ChromedPage<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    /// Given how far down the content starts. Scrolling content takes it as an inset so
    /// it passes under the chrome; anything else is padded down by it.
    @ViewBuilder var content: (_ topInset: CGFloat) -> Content

    @Environment(\.floatingChromeHeight) private var chromeHeight

    private var hasHeader: Bool { Header.self != EmptyView.self }

    var body: some View {
        if #available(macOS 26, *) {
            let topInset = chromeHeight + (hasHeader ? contentHeaderHeight : 0) + 1
            content(topInset)
                .environment(\.pageTopInset, topInset)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        header.environment(\.contentHeaderFloats, true)
                        Divider()
                    }
                    .padding(.top, chromeHeight)
                    // One surface for the header and the chrome above it. Two adjacent
                    // ones each fade their blur out towards the seam, so content crossing
                    // it vanished for a moment.
                    .background(.bar)
                }
        } else {
            VStack(spacing: 0) {
                if hasHeader {
                    header
                    Divider()
                }
                content(0)
            }
        }
    }
}

extension ChromedPage where Header == EmptyView {
    init(@ViewBuilder content: @escaping (_ topInset: CGFloat) -> Content) {
        self.init(header: { EmptyView() }, content: content)
    }
}
#endif
