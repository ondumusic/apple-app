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
    @State private var albumSelection: Set<Album.ID> = []
    @State private var songsHeight: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    private static let artistCell: CGFloat = 108
    private static let artistSpacing: CGFloat = 12
    private static let horizontalPadding: CGFloat = 20
    /// The tracks table's own leading inset, measured off a render. Cancelling exactly
    /// this much puts the row artwork on the same line as the album covers above it.
    private static let songsTableInset: CGFloat = 6
    /// Taller than the detail views' 40: results stack the artist under the title, and
    /// 40 clipped the two lines against the selection pill.
    private static let songRowHeight: CGFloat = 48

    private let artistColumns = [GridItem(.adaptive(minimum: SearchViewMac.artistCell), spacing: SearchViewMac.artistSpacing)]

    /// How many cells the adaptive grid will fit across — the same arithmetic LazyVGrid
    /// does. Used to trim the results to whole rows: capping the region by height instead
    /// sliced the last row of covers in half and left it scrolling inside a short band.
    private func perRow(cell: CGFloat, spacing: CGFloat) -> Int {
        let available = contentWidth - 2 * Self.horizontalPadding
        guard available > 0 else { return 1 }
        return max(1, Int((available + spacing) / (cell + spacing)))
    }

    /// Every section is a top-results summary — one row each of artists and albums, a
    /// handful of songs — so all three fit on screen together. The rest of each lives
    /// behind "Show all".
    private var shownArtists: [Artist] {
        Array(results.artists.prefix(perRow(cell: Self.artistCell, spacing: Self.artistSpacing)))
    }

    /// The grid itself decides how many fit; trim to one row of them.
    private var shownAlbums: [Album] {
        Array(results.albums.prefix(AlbumsGridViewController.columns(forWidth: contentWidth)))
    }

    private var shownTracks: [Track] {
        Array(results.tracks.prefix(Self.shownSongLimit))
    }

    private static let shownSongLimit = 6

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
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if !results.artists.isEmpty { artistsSection }
                if !results.albums.isEmpty { albumsSection }
                if !results.tracks.isEmpty { songsSection }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Same surface the tracks table paints, so the grids above it read as one page
        // rather than a separate panel stuck on top.
        .background(Color(NSColor.controlBackgroundColor))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    private func sectionHeader(_ title: String, count: Int, unit: String,
                               showAll: SearchAllRequest.Kind? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(countLabel(count, unit: unit))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let showAll {
                NavigationLink(value: SearchAllRequest(kind: showAll, query: query)) {
                    HStack(spacing: 3) {
                        Text("Show all")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Artists", count: results.artists.count, unit: "artist",
                          showAll: shownArtists.count < results.artists.count ? .artists : nil)
            LazyVGrid(columns: artistColumns, alignment: .leading, spacing: 14) {
                ForEach(shownArtists) { artist in
                    SearchArtistCell(artist: artist, artworkURL: artistArtwork[artist.id])
                }
            }
        }
    }

    /// The library's own grid and table rather than bespoke rows: results then select,
    /// open or play on double-click, drag into Up Next and onto playlists, and take the
    /// same context menus as everywhere else. Both are embedded, so this page keeps the
    /// scroll and each is framed to its content.
    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Albums", count: results.albums.count, unit: "album",
                          showAll: shownAlbums.count < results.albums.count ? .albums : nil)
            AlbumsGrid(
                albums: shownAlbums,
                selection: $albumSelection,
                actions: .standard(player: player, musicLibrary: musicLibrary,
                                   network: network, downloadService: downloadService),
                accent: settings.resolvedAccentColor,
                onOpen: { NotificationCenter.default.post(name: .navigateToAlbum, object: $0) },
                embedded: true
            )
            .frame(height: AlbumsGridViewController.height(forWidth: contentWidth, rows: 1,
                                                          embedded: true))
            // The grid carries its own section inset; the page's padding would double it.
            .padding(.horizontal, -Self.horizontalPadding)
        }
    }

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Songs", count: results.tracks.count, unit: "song",
                          showAll: shownTracks.count < results.tracks.count ? .songs : nil)
            TracksTable(
                tracks: shownTracks,
                selection: $trackSelection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: true,
                showAlbum: false,
                showsArtwork: true,
                showTrackNumber: false,
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: Self.songRowHeight,
                embeddedStyle: true,
                onContentHeightChange: { songsHeight = $0 }
            )
            .frame(height: max(songsHeight, CGFloat(shownTracks.count) * Self.songRowHeight))
            // The table carries its own cell inset; the page's padding on top of it
            // pushed every row in past its section header.
            .padding(.horizontal, -Self.songsTableInset)
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
