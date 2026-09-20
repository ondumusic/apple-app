#if os(macOS)
import SwiftUI

struct AlbumsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    // Same defaults keys as the iOS list, so the choice follows across platforms.
    @AppStorage("albumListSort") private var sortOption: AlbumSortOption = .artist
    @AppStorage("albumListSortAscending") private var sortAscending: Bool = true
    @State private var albums: [Album] = []
    @State private var selection: Set<Album.ID> = []

    var body: some View {
        AlbumsGrid(
            albums: albums,
            selection: $selection,
            actions: .standard(
                player: player,
                musicLibrary: musicLibrary,
                network: network,
                downloadService: downloadService
            ),
            accent: settings.resolvedAccentColor,
            onOpen: { NotificationCenter.default.post(name: .navigateToAlbum, object: $0) }
        )
        .background(Color(NSColor.controlBackgroundColor))
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
        let present = Set(albums.map(\.id))
        selection = selection.filter(present.contains)
    }
}
#endif
