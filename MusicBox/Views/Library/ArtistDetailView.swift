import SwiftUI

struct ArtistDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(OfflineStore.self) private var offlineStore

    let artist: Artist

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        let albums = musicLibrary.albumsForArtist(artist.id)
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
                                guard let fullAlbum = musicLibrary.albumWithTracks(album.id) else { return }
                                downloadService.download(album: fullAlbum, artist: artist)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            }
        }
    }

    private func playAll(shuffle: Bool) {
        let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
        let items = albums.flatMap { album in
            (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
        }
        guard !items.isEmpty else { return }
        if shuffle {
            player.playShuffled(queue: items)
        } else {
            player.playNow(queue: items)
        }
    }
}
