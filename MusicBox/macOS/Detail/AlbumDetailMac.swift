#if os(macOS)
import SwiftUI

struct AlbumDetailMac: View {
    let album: Album

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []

    private var hasMultipleArtists: Bool {
        Set(tracks.map(\.artist.id)).count > 1
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network, artworkURL: album.artworkUrl)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: hasMultipleArtists,
                showAlbum: false,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying
            )
        }
        .navigationTitle(album.name)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ArtworkView(url: album.artworkUrl)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let artistName = album.artistName {
                        Text(artistName)
                    }
                    if let year = album.releaseYear {
                        Text("•").foregroundStyle(.tertiary)
                        Text(String(year))
                    }
                    Text("•").foregroundStyle(.tertiary)
                    Text("^[\(tracks.count) song](inflect: true)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button { playAll(shuffle: false) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(tracks.isEmpty)
                Button { playAll(shuffle: true) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .disabled(tracks.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func reload() {
        tracks = musicLibrary.tracksForAlbum(album.id)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay {
            player.playNow(tracks: queue, startingAt: queueIndex, artworkURL: album.artworkUrl)
        }
    }

    private func playAll(shuffle: Bool) {
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available, artworkURL: album.artworkUrl) }
        } else {
            player.requestPlay { player.playNow(tracks: available, artworkURL: album.artworkUrl) }
        }
    }
}
#endif
