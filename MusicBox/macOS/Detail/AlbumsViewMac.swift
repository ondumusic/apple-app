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
            HStack {
                Spacer()
                sortMenu
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

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
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: sortOption) { reload() }
        .onChange(of: sortAscending) { reload() }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AlbumSortOption.allCases, id: \.self) { option in
                Button {
                    if sortOption == option {
                        sortAscending.toggle()
                    } else {
                        sortOption = option
                        sortAscending = true
                    }
                } label: {
                    if sortOption == option {
                        Label(option.rawValue, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            Label(sortLabel, systemImage: "arrow.up.arrow.down")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort Albums")
    }

    private var sortLabel: String {
        "\(sortOption.rawValue) · \(sortAscending ? sortOption.ascendingLabel : sortOption.descendingLabel)"
    }

    private func reload() {
        let source = libraryFilter == .downloaded ? musicLibrary.downloadedAlbums() : musicLibrary.allAlbums()
        albums = sortOption.sorted(source, ascending: sortAscending)
    }
}
#endif
