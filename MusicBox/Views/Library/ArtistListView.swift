import SwiftUI

struct ArtistListView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(APIService.self) private var api
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        let list = library.artists
        List(list.identifiableItems) { item in
            if let artist = item.value {
                NavigationLink(value: artist) {
                    ArtistCard(artist: artist)
                }
                .contextMenu {
                    Button {
                        Task {
                            let tracks = try? await api.fetchAllTracks(artistId: artist.id)
                            if let tracks, !tracks.isEmpty { player.playNext(tracks: tracks) }
                        }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }

                    Button {
                        Task {
                            let tracks = try? await api.fetchAllTracks(artistId: artist.id)
                            if let tracks, !tracks.isEmpty { player.addToEnd(tracks: tracks) }
                        }
                    } label: {
                        Label("Add to Queue", systemImage: "text.append")
                    }

                    Divider()

                    Button {
                        Task {
                            guard let albumStubs = try? await api.fetchAllAlbums(for: artist.id) else { return }
                            for stub in albumStubs {
                                guard let album = try? await api.fetchAlbum(stub.id) else { continue }
                                downloadService.download(album: album, artist: artist)
                            }
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .onAppear { list.itemAppeared(at: item.index) }
            } else {
                HStack(spacing: 12) {
                    Circle().fill(.quaternary).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 60, height: 12)
                    }
                    Spacer()
                }
                .onAppear { list.itemAppeared(at: item.index) }
            }
        }
        .scrollPosition($scrollPosition)
        .navigationTitle("Artists")
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .onAppear { list.loadInitialIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if let error = list.error, list.isEmpty {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}
