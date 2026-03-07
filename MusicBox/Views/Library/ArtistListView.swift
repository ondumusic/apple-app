import SwiftUI

struct ArtistListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(OfflineStore.self) private var offlineStore
    @Environment(SyncService.self) private var syncService
    @Environment(NetworkMonitor.self) private var network
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        let artists = musicLibrary.allArtists()
        List(artists) { artist in
            NavigationLink(value: artist) {
                ArtistCard(artist: artist)
            }
            .contextMenu {
                Button {
                    let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
                    let items = albums.flatMap { album in
                        (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
                    }
                    let available = offlineStore.availableItems(items, isOnline: network.isOnline)
                    guard !available.isEmpty else { return }
                    player.playNext(queue: available)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
                    let items = albums.flatMap { album in
                        (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
                    }
                    let available = offlineStore.availableItems(items, isOnline: network.isOnline)
                    guard !available.isEmpty else { return }
                    player.addToEnd(queue: available)
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Divider()

                if offlineStore.isArtistDownloaded(artistId: artist.id) {
                    Button(role: .destructive) {
                        offlineStore.deleteArtist(artistId: artist.id)
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else {
                    Button {
                        let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
                        for album in albums {
                            downloadService.download(album: album, artist: artist)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
        .scrollPosition($scrollPosition)
        .refreshable { await syncService.sync() }
        .navigationTitle("Artists")
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if artists.isEmpty {
                ContentUnavailableView("No Artists", systemImage: "music.mic")
            }
        }
    }
}
