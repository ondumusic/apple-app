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
        ChromedPage {
            ContentHeader(backDestination: nil) {
                LibraryOptionsMenu(filter: $libraryFilter) {
                    SortOptionsSection(selection: $sortOption, ascending: $sortAscending)
                }
            }
        } content: { topInset in
            if albums.isEmpty {
                LibraryEmptyState(subject: .albums, isFiltered: libraryFilter == .downloaded) {
                    libraryFilter = .all
                }
                .padding(.top, topInset)
            } else {
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
                    onOpen: { NotificationCenter.default.post(name: .navigateToAlbum, object: $0) },
                    claimsKeyboardFocus: true,
                    topContentInset: topInset
                )
                .pageBackground()
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: sortOption) { reload() }
        .onChange(of: sortAscending) { reload() }
        // Switching the ordering resets the direction to what that ordering means, which
        // is the only reason anyone picks it. Flipping it afterwards still sticks.
        .onChange(of: sortOption) { sortAscending = sortOption.defaultAscending }
    }

    private func reload() {
        let source = libraryFilter == .downloaded ? musicLibrary.downloadedAlbums() : musicLibrary.allAlbums()
        albums = sortOption.sorted(source, ascending: sortAscending, playStats: playStats())
        let present = Set(albums.map(\.id))
        selection = selection.filter(present.contains)
    }

    /// Skipped unless the chosen sort needs it: it's a pass over every played track.
    private func playStats() -> [UUID: MusicLibrary.AlbumPlayStats] {
        sortOption.needsPlayStats ? musicLibrary.albumPlayStats() : [:]
    }
}
#endif
