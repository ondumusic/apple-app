import SwiftUI

struct ArtistDetailView: View {
    @Environment(LibraryViewModel.self) private var library

    let artist: Artist

    @State private var list: PaginatedList<Album>?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if let list {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(list.identifiableItems) { item in
                        if let album = item.value {
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .onAppear { list.itemAppeared(at: item.index) }
                        } else {
                            AlbumCardPlaceholder()
                                .onAppear { list.itemAppeared(at: item.index) }
                        }
                    }
                }
                .padding()

                if let error = list.error {
                    Text(error).foregroundStyle(.red).padding()
                }
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .onAppear {
            if list == nil {
                let l = library.albumList(for: artist)
                list = l
                l.loadInitialIfNeeded()
            }
        }
    }
}
