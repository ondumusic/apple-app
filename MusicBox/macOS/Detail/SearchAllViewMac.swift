#if os(macOS)
import SwiftUI

/// Full list for one entity type from a search, reached from a section's "Show all".
/// The results page trims artists and albums to whole rows; this is where the rest live.
nonisolated struct SearchAllRequest: Hashable {
    nonisolated enum Kind: Hashable {
        case artists
        case albums
        case songs
    }

    let kind: Kind
    let query: String
}

struct SearchAllViewMac: View {
    let request: SearchAllRequest

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @State private var artists: [Artist] = []
    @State private var albums: [Album] = []
    @State private var tracks: [Track] = []
    @State private var trackSelection: Set<UUID> = []
    @State private var albumSelection: Set<Album.ID> = []
    @State private var artistArtwork: [UUID: URL] = [:]

    private let artistColumns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if request.kind == .songs {
                // The full table, which is what the results page's summary list stands in
                // for — column headers, sorting and multi-select all come back here.
                TracksTable(
                    tracks: tracks,
                    selection: $trackSelection,
                    onPlay: playTrack(at:),
                    actions: .standard(player: player, musicLibrary: musicLibrary,
                                       network: network, downloadService: downloadService),
                    showArtist: true,
                    showAlbum: true,
                    accent: settings.resolvedAccentColor,
                    currentlyPlayingTrackId: player.currentTrack?.id,
                    isPlaying: player.isPlaying
                )
            } else if request.kind == .albums {
                // The library's own grid, so results select, open on double-click and
                // drag exactly like every other album in the app.
                AlbumsGrid(
                    albums: albums,
                    selection: $albumSelection,
                    actions: .standard(player: player, musicLibrary: musicLibrary,
                                       network: network, downloadService: downloadService),
                    accent: settings.resolvedAccentColor,
                    onOpen: { NotificationCenter.default.post(name: .navigateToAlbum, object: $0) }
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: artistColumns, alignment: .leading, spacing: 14) {
                        ForEach(artists) { artist in
                            SearchArtistCell(artist: artist, artworkURL: artistArtwork[artist.id])
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
    }

    private var title: String {
        switch request.kind {
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            switch request.kind {
            case .artists:
                Text("^[\(artists.count) artist](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .albums:
                Text("^[\(albums.count) album](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .songs:
                Text("^[\(tracks.count) song](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("matching “\(request.query)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func reload() {
        let results = musicLibrary.search(request.query)
        artists = results.artists
        albums = results.albums
        tracks = results.tracks
        artistArtwork = musicLibrary.artistArtwork(for: results.artists)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: queueIndex) }
    }
}

/// Circular artwork cell used for artist results in both the search page and its
/// "show all" list. Artists have no artwork of their own — this is their first album's.
struct SearchArtistCell: View {
    let artist: Artist
    let artworkURL: URL?

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .navigateToArtist, object: artist)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let artworkURL {
                        ArtworkView(url: artworkURL)
                    } else {
                        Image(systemName: "music.mic")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                Text(artist.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 96)
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
