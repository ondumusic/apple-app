#if os(macOS)
import SwiftUI

/// Applies a window title only when this view is the one the window is showing. A view
/// embedded inside another's pane must leave the titlebar alone entirely — setting an
/// empty title still wins over the parent's, which left the title line blank.
private struct WindowTitleModifier: ViewModifier {
    let title: LocalizedStringKey?
    let subtitle: LocalizedStringKey

    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

extension View {
    func windowTitle(_ title: LocalizedStringKey?, subtitle: LocalizedStringKey) -> some View {
        modifier(WindowTitleModifier(title: title, subtitle: subtitle))
    }
}
#endif
