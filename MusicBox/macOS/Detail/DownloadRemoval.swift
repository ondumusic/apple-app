#if os(macOS)
import SwiftUI

/// Removing downloads deletes files, so every entry point asks first. Routed through a
/// notification because the requests come from AppKit menu actions, SwiftUI buttons and
/// context menus alike — one confirmation, one wording, wherever it's triggered.
nonisolated struct DownloadRemovalRequest: Sendable {
    let trackIds: Set<UUID>
    /// What's being removed, as it should read in the dialog title.
    let subject: String
}

extension Notification.Name {
    static let requestRemoveDownload = Notification.Name("MusicBox.requestRemoveDownload")
}

extension DownloadRemovalRequest {
    static func post(trackIds: Set<UUID>, subject: String) {
        guard !trackIds.isEmpty else { return }
        NotificationCenter.default.post(
            name: .requestRemoveDownload,
            object: DownloadRemovalRequest(trackIds: trackIds, subject: subject)
        )
    }

    /// "3 songs" — for selections that have no better name than their size.
    static func songSubject(count: Int) -> String {
        String(AttributedString(localized: "^[\(count) song](inflect: true)").characters)
    }
}

private struct RemoveDownloadConfirmation: ViewModifier {
    @Environment(MusicLibrary.self) private var musicLibrary
    @State private var pending: DownloadRemovalRequest?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .requestRemoveDownload)) { note in
                pending = note.object as? DownloadRemovalRequest
            }
            .confirmationDialog(
                pending.map { "Remove Download for “\($0.subject)”?" } ?? "",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let pending { musicLibrary.markTracksUndownloaded(trackIds: pending.trackIds) }
                    pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("The files are deleted from this Mac. Everything stays in your library and can be downloaded again.")
            }
    }
}

extension View {
    func removeDownloadConfirmation() -> some View {
        modifier(RemoveDownloadConfirmation())
    }
}
#endif
