#if os(macOS)
import SwiftUI

struct AlbumsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    // Same defaults keys as the iOS list, so the choice follows across platforms.
    @AppStorage("albumListSort") private var sortOption: AlbumSortOption = .artist
    @AppStorage("albumListSortAscending") private var sortAscending: Bool = true
    @State private var albums: [Album] = []

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AlbumContextMenuItems(album: album)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Albums")
        // The count belongs in the window subtitle, which is where macOS puts secondary
        // information about what's on screen. As an in-page header it cost a row of
        // vertical space on every view and repeated what the sidebar selection says.
        .navigationSubtitle("^[\(albums.count) album](inflect: true)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                LibraryOptionsMenu(filter: $libraryFilter) {
                    SortOptionsSection(selection: $sortOption, ascending: $sortAscending)
                }
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: sortOption) { reload() }
        .onChange(of: sortAscending) { reload() }
    }

    private func reload() {
        let source = libraryFilter == .downloaded ? musicLibrary.downloadedAlbums() : musicLibrary.allAlbums()
        albums = sortOption.sorted(source, ascending: sortAscending)
    }
}
#endif
