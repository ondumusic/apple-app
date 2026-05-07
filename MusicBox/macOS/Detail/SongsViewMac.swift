#if os(macOS)
import SwiftUI

struct SongsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []

    var body: some View {
        TracksTable(
            tracks: tracks,
            selection: $selection,
            onPlay: playTrack(at:),
            actions: trackActions,
            showArtist: true,
            showAlbum: true
        )
        .navigationTitle("Songs")
        .onChange(of: musicLibrary.revision, initial: true) {
            tracks = musicLibrary.allTracks()
        }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: queueIndex) }
    }
}
#endif
