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
        TracksTable(
            tracks: tracks,
            selection: $selection,
            onPlay: playTrack(at:),
            actions: trackActions,
            showArtist: true,
            showAlbum: true,
            accent: settings.resolvedAccentColor,
            currentlyPlayingTrackId: player.currentTrack?.id,
            isPlaying: player.isPlaying
        )
        .navigationTitle("Songs")
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private func reload() {
        tracks = libraryFilter == .downloaded ? musicLibrary.downloadedTracks() : musicLibrary.allTracks()
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
