#if os(macOS)
import SwiftUI

/// Reports a failed artwork change with something to do about it.
///
/// The kinds differ in what would help: a rejected image wants a different one, where a
/// failed request wants the same one again. An alert whose only button is OK leaves
/// whoever hit it to work that out and start over by hand.
struct ArtworkFailureAlert: ViewModifier {
    @Binding var failure: ArtistArtworkEditor.Failure?
    let retry: () -> Void
    let chooseAnother: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't Update Artwork",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { failure in
            switch failure {
            case .notAnImage, .tooLarge:
                Button("Choose Another…") { self.failure = nil; chooseAnother() }
                Button("Cancel", role: .cancel) { self.failure = nil }
            case .failed:
                Button("Try Again") { self.failure = nil; retry() }
                Button("Cancel", role: .cancel) { self.failure = nil }
            case .notSignedIn:
                Button("OK", role: .cancel) { self.failure = nil }
            }
        } message: { failure in
            Text(failure.message)
        }
    }
}

extension View {
    func artworkFailureAlert(
        _ failure: Binding<ArtistArtworkEditor.Failure?>,
        retry: @escaping () -> Void,
        chooseAnother: @escaping () -> Void
    ) -> some View {
        modifier(ArtworkFailureAlert(failure: failure, retry: retry, chooseAnother: chooseAnother))
    }
}
#endif
