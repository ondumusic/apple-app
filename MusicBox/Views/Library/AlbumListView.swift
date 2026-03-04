import SwiftUI

struct AlbumListView: View {
    @Environment(LibraryViewModel.self) private var library

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
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .onAppear { list.loadInitialIfNeeded() }
    }
}
