#if os(macOS)
import SwiftUI

/// The strip directly under the player row, carrying whatever the current view needs:
/// a way back on the left, the view's controls on the right.
///
/// Music.app puts its filter menu and search in exactly this position — top-right of the
/// content column, below the player row — which is where these lived before the window
/// lost its toolbar.
struct ContentHeader<Trailing: View>: View {
    static var height: CGFloat { 38 }

    var backDestination: String?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    @State private var isHoveringBack = false

    var body: some View {
        HStack(spacing: 8) {
            if let backDestination {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.medium))
                        Text(backDestination)
                    }
                    // The glyph and label are smaller than the target, so without this
                    // only the text itself would take the hover and the click.
                    .contentShape(Rectangle())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
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

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 14)
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
