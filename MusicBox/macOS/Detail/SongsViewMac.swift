#if os(macOS)
import SwiftUI

struct SongsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(backDestination: nil) {
                LibraryOptionsMenu(filter: $libraryFilter)
            }
            Divider()
            if tracks.isEmpty {
                LibraryEmptyState(subject: .songs, isFiltered: libraryFilter == .downloaded) {
                    libraryFilter = .all
                }
            } else {
            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: true,
                showAlbum: true,
                isOffline: !network.isOnline,
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                rowHeight: DetailPageMetrics.trackRowHeight
            )
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private func reload() {
        guard libraryFilter != .downloaded else {
            tracks = musicLibrary.downloadedTracks()
            return
        }
        if let warm = musicLibrary.cachedAllTracks {
            tracks = warm
            return
        }
        // Cold cache — build it off the main actor rather than freezing the window. On a
        // slower Mac the fetch-and-build is long enough to read as a hang. Whatever was
        // on screen stays until the real list arrives.
        Task {
            await musicLibrary.prepareAllTracks()
            if libraryFilter != .downloaded { tracks = musicLibrary.cachedAllTracks ?? [] }
        }
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network, downloadService: downloadService)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: queueIndex) }
    }
}
#endif
