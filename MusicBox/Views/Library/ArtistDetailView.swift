import SwiftUI

struct ArtistDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @Environment(\.dismiss) private var dismiss

    let artist: Artist
    var downloadedOnly: Bool = false

    @State private var albums: [Album] = []
    @State private var hasLoadedOnce: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            HStack(spacing: 12) {
                Button {
                    playAll(shuffle: false)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    playAll(shuffle: true)
                } label: {
                    Label("Shuffle All", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.horizontal)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AlbumContextMenuItems(album: album, artist: artist, downloadedOnly: downloadedOnly)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ArtistContextMenuItems(artist: artist, downloadedOnly: downloadedOnly)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) {
            albums = downloadedOnly
                ? musicLibrary.downloadedAlbumsForArtist(artist.id)
                : musicLibrary.albumsForArtist(artist.id)

            if downloadedOnly && hasLoadedOnce && albums.isEmpty {
                dismiss()
            }
            hasLoadedOnce = true
        }
    }

    private func playAll(shuffle: Bool) {
        let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
        let allItems = albums.flatMap { album in
            (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
        }
        let items = musicLibrary.availableItems(allItems, isOnline: network.isOnline)
        guard !items.isEmpty else { return }
        if shuffle {
            player.playShuffled(queue: items)
        } else {
            player.playNow(queue: items)
        }
    }
}
