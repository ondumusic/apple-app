#if os(macOS)
import SwiftUI

struct ArtistsViewMac: View {
    /// When non-nil, the master list selects this artist on first load instead of
    /// defaulting to artists.first. MacOSContentView sets it from .navigateToArtist
    /// so opening this view from "Go to Artist" lands directly on the right artist
    /// without flickering through the default first-artist selection.
    @Binding var pendingArtistSelection: UUID?

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    @State private var artists: [Artist] = []
    @State private var selectedArtistId: Artist.ID?

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(backDestination: nil) {
                LibraryOptionsMenu(filter: $libraryFilter)
            }
            Divider()
            // Plain HStack with a manual divider — HSplitView was rendering above the
            // window toolbar (it doesn't respect the parent's toolbar safe area), and the
            // nested NavigationSplitView had its own grey chrome problem. A regular HStack
            // sits cleanly inside the outer detail column.
            HStack(spacing: 0) {
                ArtistsTable(
                    artists: artists,
                    selection: $selectedArtistId,
                    actions: .standard(
                        player: player,
                        musicLibrary: musicLibrary,
                        network: network,
                        downloadService: downloadService
                    ),
                    accent: settings.resolvedAccentColor
                )
                .background(.background)
                .frame(width: 240)

                Divider()

                Group {
                    if let id = selectedArtistId, let artist = artists.first(where: { $0.id == id }) {
                        ArtistDetailMac(artist: artist, isEmbedded: true)
                            .id(artist.id)
                    } else {
                        ContentUnavailableView("Select an Artist", systemImage: "music.mic")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) { reloadArtists() }
        .onChange(of: libraryFilter) { reloadArtists() }
        .onChange(of: pendingArtistSelection) { _, newValue in
            // Late navigation while ArtistsViewMac is already onscreen.
            if let id = newValue, artists.contains(where: { $0.id == id }) {
                selectedArtistId = id
                pendingArtistSelection = nil
            }
        }
    }

    private func reloadArtists() {
        artists = libraryFilter == .downloaded ? musicLibrary.downloadedArtists() : musicLibrary.allArtists()
        // Prefer a pending navigation request, then keep current, then fall back to the
        // first artist. The pending value is consumed once.
        if let pending = pendingArtistSelection, artists.contains(where: { $0.id == pending }) {
            selectedArtistId = pending
            pendingArtistSelection = nil
        } else if selectedArtistId == nil || !artists.contains(where: { $0.id == selectedArtistId }) {
            selectedArtistId = artists.first?.id
        }
    }
}
#endif
