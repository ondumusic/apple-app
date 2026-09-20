#if os(macOS)
import SwiftUI

private struct PushedContentHeader: ViewModifier {
    let destination: String?

    func body(content: Content) -> some View {
        if let destination {
            VStack(spacing: 0) {
                ContentHeader(backDestination: destination)
                Divider()
                content
            }
            // NavigationStack supplies its own back button once something is pushed,
            // and a toolbar to hold it — which showed as a stray chevron beside the
            // traffic lights. Hiding the button is enough; hiding the whole window
            // toolbar also removes close, minimise and zoom.
            .navigationBarBackButtonHidden(true)
        } else {
            content
        }
    }
}

extension View {
    /// Puts the back strip above a pushed view, naming where it returns to. The window
    /// has no toolbar to hang a back button on, and Music.app keeps its own in this same
    /// position — top-left of the content column, under the player row.
    func contentHeader(_ backDestination: String?) -> some View {
        modifier(PushedContentHeader(destination: backDestination))
    }
}
#endif
