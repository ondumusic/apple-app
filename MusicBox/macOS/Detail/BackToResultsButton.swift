#if os(macOS)
import SwiftUI

/// Back control for pushed detail views, labelled with where it returns to rather than
/// with the current page — the page's own header already says where you are, and a bare
/// chevron doesn't say what it does. This is the behaviour NavigationStack gives on iOS;
/// macOS only offers the chevron, so the native one is replaced.
///
/// It's a real toolbar item again now that the player has moved out of the toolbar. It
/// previously had to be a faux in-page bar because `.navigation` placement put it beside
/// the transport controls, where it read as a player control.
private struct BackToolbarModifier: ViewModifier {
    let destination: String?
    @Environment(\.dismiss) private var dismiss
    @State private var isHovering = false

    func body(content: Content) -> some View {
        if let destination {
            content
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button { dismiss() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.backward")
                                    .font(.body.weight(.medium))
                                Text(destination)
                            }
                        }
                        .buttonStyle(.plain)
                        // Plain loses the hover highlight along with the border, and
                        // toolbar buttons do highlight on macOS — Finder's back and
                        // forward both do. This puts the feedback back without the
                        // permanent bezel.
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(isHovering ? 0.10 : 0))
                        }
                        .onHover { isHovering = $0 }
                        .help("Back to \(destination)")
                        .accessibilityLabel("Back to \(destination)")
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Labels the toolbar's back control with the view it returns to.
    func backToolbar(_ destination: String?) -> some View {
        modifier(BackToolbarModifier(destination: destination))
    }
}
#endif
