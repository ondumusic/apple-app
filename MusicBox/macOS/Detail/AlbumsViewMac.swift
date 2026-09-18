#if os(macOS)
import SwiftUI

struct AlbumsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    // Same defaults keys as the iOS list, so the choice follows across platforms.
    @AppStorage("albumListSort") private var sortOption: AlbumSortOption = .artist
    @AppStorage("albumListSortAscending") private var sortAscending: Bool = true
    @State private var albums: [Album] = []
    @State private var selection: Set<UUID> = []
    /// Anchor for shift-click range selection — the last album clicked without a modifier.
    @State private var selectionAnchor: Int?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                    AlbumGridItem(
                        album: album,
                        isSelected: selection.contains(album.id),
                        accent: settings.resolvedAccentColor,
                        onClick: { click(index: index) },
                        onOpen: { open(album) }
                    )
                    .contextMenu {
                        // Right-clicking inside a multi-selection acts on all of it;
                        // right-clicking outside one acts on just that album, without
                        // disturbing what's selected.
                        if selection.count > 1, selection.contains(album.id) {
                            AlbumsContextMenuItems(albums: albums.filter { selection.contains($0.id) })
                        } else {
                            AlbumContextMenuItems(album: album)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { selection = [] }
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

    /// Click-to-select, matching every other list in the app; double-click opens. Cmd
    /// toggles one, Shift extends from the last plain click.
    private func click(index: Int) {
        let album = albums[index]
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(album.id) {
                selection.remove(album.id)
            } else {
                selection.insert(album.id)
                selectionAnchor = index
            }
        } else if flags.contains(.shift), let anchor = selectionAnchor {
            let range = anchor <= index ? anchor...index : index...anchor
            selection = Set(range.map { albums[$0].id })
        } else {
            selection = [album.id]
            selectionAnchor = index
        }
    }

    private func open(_ album: Album) {
        selection = [album.id]
        NotificationCenter.default.post(name: .navigateToAlbum, object: album)
    }

    private func reload() {
        let source = libraryFilter == .downloaded ? musicLibrary.downloadedAlbums() : musicLibrary.allAlbums()
        albums = sortOption.sorted(source, ascending: sortAscending)
        let present = Set(albums.map(\.id))
        selection = selection.filter(present.contains)
    }
}
/// Hover was missing entirely: nothing about a card changed until the click had already
/// happened. The highlight sits behind the card rather than on the artwork so a pale
/// cover doesn't lose its own border to it.
private struct AlbumGridItem: View {
    let album: Album
    let isSelected: Bool
    let accent: Color
    let onClick: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        AlbumCard(album: album)
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(fill)
            }
            .contentShape(Rectangle())
            // Declared before the single-click handler so SwiftUI resolves the pair in
            // the right order — the other way round, the first click always wins.
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(count: 1, perform: onClick)
            .onHover { isHovering = $0 }
    }

    private var fill: Color {
        if isSelected { return accent.opacity(0.22) }
        return isHovering ? Color.primary.opacity(0.07) : .clear
    }
}

#endif
