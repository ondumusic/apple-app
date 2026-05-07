#if os(macOS)
import SwiftUI

struct PlaylistDetailMac: View {
    let playlistId: UUID

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @State private var playlist: Playlist?
    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: true,
                showAlbum: true
            )
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: playlistId) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist?.name ?? "")
                    .font(.title2.bold())
                Text("^[\(tracks.count) song](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { playAll(shuffle: false) } label: {
                Label("Play", systemImage: "play.fill")
            }
            .disabled(tracks.isEmpty)
            Button { playAll(shuffle: true) } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .disabled(tracks.isEmpty)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func reload() {
        playlist = musicLibrary.playlist(playlistId)
        tracks = musicLibrary.tracksForPlaylist(playlistId)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: queueIndex) }
    }

    private func playAll(shuffle: Bool) {
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available) }
        } else {
            player.requestPlay { player.playNow(tracks: available) }
        }
    }
}
#endif
