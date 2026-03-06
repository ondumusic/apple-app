import SwiftUI

struct AlbumListView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(APIService.self) private var api
    @State private var scrollPosition = ScrollPosition()

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        let list = library.albums
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(list.identifiableItems) { item in
                    if let album = item.value {
                        NavigationLink(value: album) {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task {
                                    guard let full = try? await api.fetchAlbum(album.id),
                                          let tracks = full.tracks, !tracks.isEmpty else { return }
                                    player.playNext(tracks: tracks, artworkURL: full.artworkUrl)
                                }
                            } label: {
                                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }

                            Button {
                                Task {
                                    guard let full = try? await api.fetchAlbum(album.id),
                                          let tracks = full.tracks, !tracks.isEmpty else { return }
                                    player.addToEnd(tracks: tracks, artworkURL: full.artworkUrl)
                                }
                            } label: {
                                Label("Add to Queue", systemImage: "text.append")
                            }

                            Divider()

                            Button {
                                Task {
                                    guard let full = try? await api.fetchAlbum(album.id),
                                          let tracks = full.tracks,
                                          let artist = tracks.first?.artist else { return }
                                    downloadService.download(album: full, artist: artist)
                                }
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                        .onAppear { list.itemAppeared(at: item.index) }
                    } else {
                        AlbumCardPlaceholder()
                            .onAppear { list.itemAppeared(at: item.index) }
                    }
                }
            }
            .padding()

            if let error = list.error, list.isEmpty {
                Text(error).foregroundStyle(.red).padding()
            }
        }
        .scrollPosition($scrollPosition)
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .onAppear { list.loadInitialIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
    }
}
