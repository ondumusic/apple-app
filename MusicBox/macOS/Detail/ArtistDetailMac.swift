#if os(macOS)
import SwiftUI

struct ArtistDetailMac: View {
    let artist: Artist

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @State private var albums: [Album] = []

    private var totalSongs: Int {
        albums.reduce(0) { $0 + ($1.tracks?.count ?? 0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                ForEach(albums) { album in
                    AlbumInlineSection(album: album, artist: artist)
                    if album.id != albums.last?.id {
                        Divider()
                    }
                }
            }
            .padding(20)
        }
        .background(.background)
        .defaultScrollAnchor(.top)
        .navigationTitle(artist.name)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) { reload() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.largeTitle.bold())
                Text("^[\(albums.count) album](inflect: true) • ^[\(totalSongs) song](inflect: true)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { playAll(shuffle: false) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(albums.isEmpty)
                Button { playAll(shuffle: true) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .disabled(albums.isEmpty)
            }
            .controlSize(.large)
        }
    }

    private func reload() {
        albums = musicLibrary.albumsWithTracksForArtist(artist.id)
    }

    private func playAll(shuffle: Bool) {
        let allItems = albums.flatMap { album in
            (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
        }
        let items = musicLibrary.availableItems(allItems, isOnline: network.isOnline)
        guard !items.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(queue: items) }
        } else {
            player.requestPlay { player.playNow(queue: items) }
        }
    }
}

private struct AlbumInlineSection: View {
    let album: Album
    let artist: Artist

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    private var tracks: [Track] { album.tracks ?? [] }
    private var hasMultipleArtists: Bool { Set(tracks.map(\.artist.id)).count > 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(value: album) {
                    ArtworkView(url: album.artworkUrl)
                        .frame(width: 160, height: 160)
                }
                .buttonStyle(.plain)
                Text(album.name)
                    .font(.headline)
                    .lineLimit(2)
                if let year = album.releaseYear {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Button { playAlbum(shuffle: false) } label: { Image(systemName: "play.fill") }
                    Button { playAlbum(shuffle: true) } label: { Image(systemName: "shuffle") }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
            .frame(width: 180, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(tracks) { track in
                    TrackRow(track: track, album: album, artist: artist, showArtist: hasMultipleArtists) {
                        playTrack(track)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func playTrack(_ track: Track) {
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let index = available.firstIndex(where: { $0.id == track.id }) else { return }
        player.requestPlay {
            player.playNow(tracks: available, startingAt: index, artworkURL: album.artworkUrl)
        }
    }

    private func playAlbum(shuffle: Bool) {
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
