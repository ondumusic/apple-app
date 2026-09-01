#if os(macOS)
import SwiftUI

struct SearchViewMac: View {
    let query: String

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @State private var results: (artists: [Artist], albums: [Album], tracks: [Track]) = ([], [], [])
    /// Artists carry no artwork of their own, so each one borrows its first album's.
    /// Resolved once per query rather than per row.
    @State private var artistArtwork: [UUID: URL] = [:]
    @State private var displayedQuery: String = ""
    @State private var trackSelection: Set<UUID> = []
    @State private var contentWidth: CGFloat = 0

    private static let artistCell: CGFloat = 108
    private static let albumCell: CGFloat = 124
    private static let artistSpacing: CGFloat = 12
    private static let albumSpacing: CGFloat = 16
    private static let horizontalPadding: CGFloat = 20

    private let artistColumns = [GridItem(.adaptive(minimum: SearchViewMac.artistCell), spacing: SearchViewMac.artistSpacing)]
    private let albumColumns = [GridItem(.adaptive(minimum: SearchViewMac.albumCell), spacing: SearchViewMac.albumSpacing)]

    /// How many cells the adaptive grid will fit across — the same arithmetic LazyVGrid
    /// does. Used to trim the results to whole rows: capping the region by height instead
    /// sliced the last row of covers in half and left it scrolling inside a short band.
    private func perRow(cell: CGFloat, spacing: CGFloat) -> Int {
        let available = contentWidth - 2 * Self.horizontalPadding
        guard available > 0 else { return 1 }
        return max(1, Int((available + spacing) / (cell + spacing)))
    }

    /// One row of artists, two of albums — this is a top-results area, not the full list.
    private var shownArtists: [Artist] {
        Array(results.artists.prefix(perRow(cell: Self.artistCell, spacing: Self.artistSpacing)))
    }

    private var shownAlbums: [Album] {
        Array(results.albums.prefix(perRow(cell: Self.albumCell, spacing: Self.albumSpacing) * 2))
    }

    private var hasTopResults: Bool { !results.artists.isEmpty || !results.albums.isEmpty }

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search Library",
                    systemImage: "magnifyingglass",
                    description: Text("Type to search artists, albums, and songs.")
                )
            } else if displayedQuery == query, results.tracks.isEmpty,
                      results.artists.isEmpty, results.albums.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                resultsBody
            }
        }
        .navigationTitle("Search")
        .task(id: query) {
            // Debounce so each keystroke doesn't fire a fetch. .task cancels when query
            // changes, so a stale closure can't overwrite results with an older match.
            guard !query.isEmpty else {
                results = ([], [], [])
                artistArtwork = [:]
                displayedQuery = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = musicLibrary.search(query)
            results = found
            artistArtwork = musicLibrary.artistArtwork(for: found.artists)
            displayedQuery = query
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasTopResults {
                VStack(alignment: .leading, spacing: 20) {
                    if !results.artists.isEmpty { artistsSection }
                    if !results.albums.isEmpty { albumsSection }
                }
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            if !results.tracks.isEmpty {
                sectionHeader("Songs", count: results.tracks.count, unit: "song")
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                TracksTable(
                    tracks: results.tracks,
                    selection: $trackSelection,
                    onPlay: playTrack(at:),
                    actions: trackActions,
                    showArtist: true,
                    showAlbum: true,
                    accent: settings.resolvedAccentColor,
                    currentlyPlayingTrackId: player.currentTrack?.id,
                    isPlaying: player.isPlaying
                )
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    private func sectionHeader(_ title: String, count: Int, unit: String,
                               showAll: SearchAllRequest.Kind? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            Text(countLabel(count, unit: unit))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let showAll {
                Spacer()
                NavigationLink(value: SearchAllRequest(kind: showAll, query: query)) {
                    HStack(spacing: 2) {
                        Text("Show all")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .buttonStyle(.link)
            }
        }
    }

    private func countLabel(_ count: Int, unit: String) -> LocalizedStringKey {
        switch unit {
        case "artist": "^[\(count) artist](inflect: true)"
        case "album": "^[\(count) album](inflect: true)"
        default: "^[\(count) song](inflect: true)"
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Artists", count: results.artists.count, unit: "artist",
                          showAll: shownArtists.count < results.artists.count ? .artists : nil)
            LazyVGrid(columns: artistColumns, alignment: .leading, spacing: 14) {
                ForEach(shownArtists) { artist in
                    SearchArtistCell(artist: artist, artworkURL: artistArtwork[artist.id])
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Albums", count: results.albums.count, unit: "album",
                          showAll: shownAlbums.count < results.albums.count ? .albums : nil)
            LazyVGrid(columns: albumColumns, alignment: .leading, spacing: 16) {
                ForEach(shownAlbums) { album in
                    Button {
                        NotificationCenter.default.post(name: .navigateToAlbum, object: album)
                    } label: {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AlbumContextMenuItems(album: album)
                    }
                }
            }
        }
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network, downloadService: downloadService)
    }

    private func playTrack(at index: Int) {
        let tracks = results.tracks
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: queueIndex) }
    }
}
#endif
