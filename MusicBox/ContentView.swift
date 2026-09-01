import SwiftUI

extension Notification.Name {
    static let scrollToTop = Notification.Name("MusicBox.scrollToTop")
    static let navigateToArtist = Notification.Name("MusicBox.navigateToArtist")
    static let navigateToAlbum = Notification.Name("MusicBox.navigateToAlbum")
    static let sessionExpired = Notification.Name("MusicBox.sessionExpired")
    /// Posted with `object: [UUID]` — the track ids to be added.
    static let requestAddToPlaylist = Notification.Name("MusicBox.requestAddToPlaylist")
    static let focusSearch = Notification.Name("MusicBox.focusSearch")
    static let toggleMiniPlayer = Notification.Name("MusicBox.toggleMiniPlayer")
    static let showDownloadActivity = Notification.Name("MusicBox.showDownloadActivity")
    static let togglePlayPause = Notification.Name("MusicBox.togglePlayPause")
    /// Posted with `object: UUID` — the playlist/folder id that should enter inline rename
    /// mode in the macOS sidebar (used for "create + immediately rename" flow).
    static let startInlineRename = Notification.Name("MusicBox.startInlineRename")
    /// Posted by MusicLibrary.remapPlaylistId when an optimistic playlist's temp id is
    /// rewritten to the server-assigned id. userInfo: ["temp": UUID, "real": UUID].
    static let playlistIdRemapped = Notification.Name("MusicBox.playlistIdRemapped")
}

struct ContentView: View {
    @Environment(SyncService.self) private var syncService
    @Environment(OutboxService.self) private var outbox

    var body: some View {
        Group {
            if syncService.hasCompletedInitialSync {
                #if os(iOS)
                iOSRootView()
                    .task {
                        await outbox.flush()
                        await syncService.syncIfNeeded()
                    }
                #else
                MacOSContentView()
                    .task {
                        await outbox.flush()
                        await syncService.syncIfNeeded()
                    }
                #endif
            } else {
                SyncProgressView()
                    .task {
                        try? await syncService.sync()
                    }
            }
        }
        .alert(
            "Playlist sync issue",
            isPresented: Binding(
                get: { outbox.lastError != nil },
                set: { if !$0 { outbox.lastError = nil } }
            ),
            presenting: outbox.lastError
        ) { _ in
            Button("OK", role: .cancel) { outbox.lastError = nil }
        } message: { message in
            Text(message)
        }
    }
}

private struct SyncProgressView: View {
    @Environment(SyncService.self) private var syncService

    var body: some View {
        VStack(spacing: 16) {
            if let error = syncService.syncError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Sync Failed")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button("Retry") {
                    Task { await syncService.sync() }
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Syncing Library...")
                    .font(.headline)
                if let progress = syncService.syncProgress {
                    Group {
                        if progress.trackCount > 0 {
                            Text("\(progress.artistCount) artists, \(progress.albumCount) albums, \(progress.trackCount) tracks")
                        } else if progress.albumCount > 0 {
                            Text("\(progress.artistCount) artists, \(progress.albumCount) albums")
                        } else if progress.artistCount > 0 {
                            Text("\(progress.artistCount) artists")
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .monospacedDigit()
                }
            }
        }
    }
}
