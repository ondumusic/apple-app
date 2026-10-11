import SwiftUI

extension Notification.Name {
    static let scrollToTop = Notification.Name("Ondu.scrollToTop")
    static let navigateToArtist = Notification.Name("Ondu.navigateToArtist")
    static let navigateToAlbum = Notification.Name("Ondu.navigateToAlbum")
    static let sessionExpired = Notification.Name("Ondu.sessionExpired")
    /// Posted with `object: [UUID]` — the track ids to be added.
    static let requestAddToPlaylist = Notification.Name("Ondu.requestAddToPlaylist")
    static let focusSearch = Notification.Name("Ondu.focusSearch")
    static let toggleMiniPlayer = Notification.Name("Ondu.toggleMiniPlayer")
    /// Swap to the mini player, closing the main window — what clicking the player row's
    /// artwork does, as in Music.app.
    static let switchToMiniPlayer = Notification.Name("Ondu.switchToMiniPlayer")
    static let newPlaylistRequested = Notification.Name("Ondu.newPlaylistRequested")
    /// Reveal whatever is playing in the library — Music.app's Go to Current Song.
    static let goToCurrentSong = Notification.Name("Ondu.goToCurrentSong")
    /// Object is a `SidebarCategory`. Menu-driven section switching.
    static let selectLibrarySection = Notification.Name("Ondu.selectLibrarySection")
    static let navigateBack = Notification.Name("Ondu.navigateBack")
    static let showDownloadActivity = Notification.Name("Ondu.showDownloadActivity")
    static let togglePlayPause = Notification.Name("Ondu.togglePlayPause")
    /// Handled by whichever surface is key — the mini player's inline queue if that
    /// panel has focus, otherwise the main window's queue slide-over.
    static let toggleUpNext = Notification.Name("Ondu.toggleUpNext")
    /// Posted with `object: UUID` — the playlist/folder id that should enter inline rename
    /// mode in the macOS sidebar (used for "create + immediately rename" flow).
    static let startInlineRename = Notification.Name("Ondu.startInlineRename")
    /// Posted by MusicLibrary.remapPlaylistId when an optimistic playlist's temp id is
    /// rewritten to the server-assigned id. userInfo: ["temp": UUID, "real": UUID].
    static let playlistIdRemapped = Notification.Name("Ondu.playlistIdRemapped")
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
    @Environment(AuthService.self) private var auth

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

                HStack(spacing: 12) {
                    // No confirmation: nothing has synced yet, so there's nothing to lose.
                    Button("Sign Out") { auth.logout() }
                        .buttonStyle(.bordered)
                    Button("Retry") {
                        Task { await syncService.sync() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            } else {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: 4) {
                    Text("Getting your library ready")
                        .font(.headline)
                    Text("The first sync can take a few minutes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let progress = syncService.syncProgress, progress.artistCount > 0 {
                    SyncCounts(
                        artists: Double(progress.artistCount),
                        albums: Double(progress.albumCount),
                        tracks: Double(progress.trackCount)
                    )
                    .animation(.easeOut(duration: 0.8), value: progress.trackCount)
                    .animation(.easeOut(duration: 0.8), value: progress.albumCount)
                    .animation(.easeOut(duration: 0.8), value: progress.artistCount)
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
                    .monospacedDigit()
                    .padding(.top, 8)
                }
            }
        }
    }
}

/// Sync pages land a few hundred rows at a time; animating the counts through every
/// value in between makes them tick up instead of jumping by the page size.
private struct SyncCounts: View, Animatable {
    var artists: Double
    var albums: Double
    var tracks: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(artists, AnimatablePair(albums, tracks)) }
        set {
            artists = newValue.first
            albums = newValue.second.first
            tracks = newValue.second.second
        }
    }

    var body: some View {
        let artistCount = Int(artists)
        let albumCount = Int(albums)
        let trackCount = Int(tracks)
        if trackCount > 0 {
            Text("\(artistCount) artists, \(albumCount) albums, \(trackCount) tracks")
        } else if albumCount > 0 {
            Text("\(artistCount) artists, \(albumCount) albums")
        } else {
            Text("\(artistCount) artists")
        }
    }
}
