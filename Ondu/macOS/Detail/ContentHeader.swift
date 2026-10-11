#if os(macOS)
import SwiftUI

/// The strip directly under the player row, carrying whatever the current view needs:
/// a way back on the left, the view's controls on the right.
///
/// Music.app puts its filter menu and search in exactly this position — top-right of the
/// content column, below the player row — which is where these lived before the window
/// lost its toolbar.
/// Shared so Up Next's header can line its bottom border up with this one's.
let contentHeaderHeight: CGFloat = 38

struct ContentHeader<Trailing: View>: View {
    static var height: CGFloat { contentHeaderHeight }

    var backDestination: String?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    @Environment(\.contentHeaderFloats) private var floats
    @State private var isHoveringBack = false

    var body: some View {
        // Floating, it's on ChromedPage's translucent surface rather than its own.
        if floats {
            strip
        } else {
            strip.pageBackground()
        }
    }

    private var strip: some View {
        HStack(spacing: Spacing.related) {
            if let backDestination {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.medium))
                        .frame(width: 22, height: 22)
                        // The glyph and label are smaller than the target, so without this
                        // only the text itself would take the hover and the click.
                        .contentShape(Rectangle())
                        .padding(.horizontal, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(isHoveringBack ? 0.10 : 0))
                        }
                }
                .buttonStyle(.plain)
                .onHover { isHoveringBack = $0 }
                .help("Back to \(backDestination)")
                .accessibilityLabel("Back to \(backDestination)")
            }

            Spacer(minLength: Spacing.related)

            trailing
        }
        .padding(.horizontal, Spacing.block)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
    }
}

extension ContentHeader where Trailing == EmptyView {
    init(backDestination: String?) {
        self.init(backDestination: backDestination, trailing: { EmptyView() })
    }
}
#endif
