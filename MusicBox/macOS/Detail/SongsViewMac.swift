#if os(macOS)
import SwiftUI

struct SongsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    /// Empty means the library's own order — album artist, album, disc, track number —
    /// which is what keeps an album's tracks together instead of interleaving them. No
    /// column expresses it, so a header click is an override, not a replacement, and the
    /// header menu's Default Order is the way back.
    @AppStorage("songsSort") private var storedSort: String = ""
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
                sort: sort,
                onSortChange: { newSort in
                    storedSort = newSort?.rawValue ?? ""
                },
                columnPreferenceKey: "songs",
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                rowHeight: DetailPageMetrics.trackRowHeight,
                claimsKeyboardFocus: true
            )
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: storedSort) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private var sort: TrackSort? { TrackSort(rawValue: storedSort) }

    private func ordered(_ source: [Track]) -> [Track] {
        sort.map { $0.sorted(source) } ?? source
    }

    private func reload() {
        guard libraryFilter != .downloaded else {
            tracks = ordered(musicLibrary.downloadedTracks())
            return
        }
        if let warm = musicLibrary.cachedAllTracks {
            tracks = ordered(warm)
            return
        }
        // Cold cache — build it off the main actor rather than freezing the window. On a
        // slower Mac the fetch-and-build is long enough to read as a hang. Whatever was
        // on screen stays until the real list arrives.
        Task {
            await musicLibrary.prepareAllTracks()
            if libraryFilter != .downloaded { tracks = ordered(musicLibrary.cachedAllTracks ?? []) }
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
