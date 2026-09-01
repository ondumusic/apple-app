#if os(macOS)
import SwiftUI

/// Full list for one entity type from a search, reached from a section's "Show all".
/// The results page trims artists and albums to whole rows; this is where the rest live.
nonisolated struct SearchAllRequest: Hashable {
    nonisolated enum Kind: Hashable {
        case artists
        case albums
    }

    let kind: Kind
    let query: String
}

struct SearchAllViewMac: View {
    let request: SearchAllRequest

    @Environment(MusicLibrary.self) private var musicLibrary

    @State private var artists: [Artist] = []
    @State private var albums: [Album] = []
    @State private var artistArtwork: [UUID: URL] = [:]

    private let artistColumns = [GridItem(.adaptive(minimum: 108), spacing: 12)]
    private let albumColumns = [GridItem(.adaptive(minimum: 124), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                switch request.kind {
                case .artists:
                    LazyVGrid(columns: artistColumns, alignment: .leading, spacing: 14) {
                        ForEach(artists) { artist in
                            SearchArtistCell(artist: artist, artworkURL: artistArtwork[artist.id])
                        }
                    }
                    .padding(20)
                case .albums:
                    LazyVGrid(columns: albumColumns, alignment: .leading, spacing: 16) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { AlbumContextMenuItems(album: album) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(title)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
    }

    private var title: String {
        switch request.kind {
        case .artists: "Artists"
        case .albums: "Albums"
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            switch request.kind {
            case .artists:
                Text("^[\(artists.count) artist](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .albums:
                Text("^[\(albums.count) album](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("matching “\(request.query)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func reload() {
        let results = musicLibrary.search(request.query)
        artists = results.artists
        albums = results.albums
        artistArtwork = musicLibrary.artistArtwork(for: results.artists)
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
