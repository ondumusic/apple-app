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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                showArtist: hasMultipleArtists,
                showAlbum: false
            )
        }
        .navigationTitle(album.name)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(url: album.artworkUrl)
                .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(album.artistName ?? "")
                    .foregroundStyle(.secondary)
                if let year = album.releaseYear {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
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
            Spacer(minLength: 0)
        }
        .padding(16)
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
