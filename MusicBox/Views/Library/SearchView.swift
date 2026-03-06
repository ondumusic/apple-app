import SwiftUI

struct SearchView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player

    let query: String

    private var results: (artists: [Artist], albums: [Album], tracks: [Track]) {
        musicLibrary.search(query)
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        let results = results
        let hasResults = !results.artists.isEmpty || !results.albums.isEmpty || !results.tracks.isEmpty

        if query.isEmpty {
            ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search for artists, albums, or songs."))
        } else if !hasResults {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if !results.artists.isEmpty {
                    Section("Artists") {
                        ForEach(results.artists.prefix(5)) { artist in
                            NavigationLink(value: artist) {
                                ArtistCard(artist: artist)
                            }
                        }
                    }
                }

                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums.prefix(5)) { album in
                            NavigationLink(value: album) {
                                HStack(spacing: 12) {
                                    ArtworkView(url: album.artworkUrl)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(album.name)
                                            .lineLimit(1)
                                        if let year = album.releaseYear {
                                            Text(String(year))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !results.tracks.isEmpty {
                    Section("Songs") {
                        ForEach(results.tracks.prefix(10)) { track in
                            TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                                let items = results.tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                                if let idx = items.firstIndex(where: { $0.track.id == track.id }) {
                                    player.playNow(queue: items, startingAt: idx)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist)
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
            }
        }
    }
}
