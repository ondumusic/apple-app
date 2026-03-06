import SwiftUI

struct AlbumListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(OfflineStore.self) private var offlineStore
    @Environment(SyncService.self) private var syncService
    @State private var scrollPosition = ScrollPosition()

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        let albums = musicLibrary.allAlbums()
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            let tracks = musicLibrary.tracksForAlbum(album.id)
                            player.playNext(tracks: tracks, artworkURL: album.artworkUrl)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }

                        Button {
                            let tracks = musicLibrary.tracksForAlbum(album.id)
                            player.addToEnd(tracks: tracks, artworkURL: album.artworkUrl)
                        } label: {
                            Label("Add to Queue", systemImage: "text.append")
                        }

                        Divider()

                        if offlineStore.isAlbumDownloaded(albumId: album.id) {
                            Button(role: .destructive) {
                                offlineStore.deleteAlbum(albumId: album.id)
                            } label: {
                                Label("Remove Download", systemImage: "trash")
                            }
                        } else {
                            Button {
                                guard let fullAlbum = musicLibrary.albumWithTracks(album.id),
                                      let artistObj = musicLibrary.artist(album.artistId) else { return }
                                downloadService.download(album: fullAlbum, artist: artistObj)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
        .refreshable { await syncService.sync() }
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            }
        }
    }
}
