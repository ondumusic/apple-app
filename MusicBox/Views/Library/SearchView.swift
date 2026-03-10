import SwiftUI

struct SearchView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(SearchHistory.self) private var searchHistory
    @Environment(NetworkMonitor.self) private var network

    let query: String

    private var results: (artists: [Artist], albums: [Album], tracks: [Track]) {
        musicLibrary.search(query)
    }

    var body: some View {
        let results = results
        let hasResults = !results.artists.isEmpty || !results.albums.isEmpty || !results.tracks.isEmpty

        if query.isEmpty {
            if searchHistory.items.isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search for artists, albums, or songs."))
            } else {
                recentsList
            }
        } else if !hasResults {
            ContentUnavailableView.search(text: query)
        } else {
            resultsList(results)
        }
    }

    // MARK: - Results

    private func resultsList(_ results: (artists: [Artist], albums: [Album], tracks: [Track])) -> some View {
        List {
            if !results.artists.isEmpty {
                Section("Artists") {
                    ForEach(results.artists.prefix(5)) { artist in
                        NavigationLink(value: artist) {
                            ArtistCard(artist: artist)
                        }
                        .tint(.primary)
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
                        .tint(.primary)
                    }
                }
            }

            if !results.tracks.isEmpty {
                Section("Songs") {
                    ForEach(results.tracks.prefix(10)) { track in
                        TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                            let allItems = results.tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                            let items = musicLibrary.availableItems(allItems, isOnline: network.isOnline)
                            if let idx = items.firstIndex(where: { $0.track.id == track.id }) {
                                player.playNow(queue: items, startingAt: idx)
                            }
                            searchHistory.add(SearchHistoryItem(
                                id: track.id, kind: .song,
                                name: track.name,
                                subtitle: track.artist.name,
                                artworkUrl: track.album?.artworkUrl,
                                artistId: track.artistId,
                                albumId: track.albumId
                            ))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
                .onAppear {
                    searchHistory.add(SearchHistoryItem(
                        id: artist.id, kind: .artist, name: artist.name
                    ))
                }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
                .onAppear {
                    let artistName = musicLibrary.artist(album.artistId)?.name
                    searchHistory.add(SearchHistoryItem(
                        id: album.id, kind: .album, name: album.name,
                        subtitle: artistName, artworkUrl: album.artworkUrl,
                        artistId: album.artistId
                    ))
                }
        }
    }

    // MARK: - Recents

    private var recentsList: some View {
        List {
            Section {
                ForEach(searchHistory.items) { item in
                    searchHistoryRow(item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                searchHistory.remove(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") {
                        searchHistory.clear()
                    }
                    .font(.caption)
                    .textCase(nil)
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

    @ViewBuilder
    private func searchHistoryRow(_ item: SearchHistoryItem) -> some View {
        switch item.kind {
        case .artist:
            if let artist = musicLibrary.artist(item.id) {
                NavigationLink(value: artist) {
                    historyLabel(item)
                }
                .tint(.primary)
            }
        case .album:
            if let album = musicLibrary.album(item.id) {
                NavigationLink(value: album) {
                    historyLabel(item)
                }
                .tint(.primary)
            }
        case .song:
            Button {
                if let track = musicLibrary.track(item.id) {
                    let queueItem = QueueItem(track: track, artworkURL: track.album?.artworkUrl)
                    player.playNow(queue: [queueItem])
                }
            } label: {
                historyLabel(item)
            }
            .tint(.primary)
        }
    }

    private func historyLabel(_ item: SearchHistoryItem) -> some View {
        HStack(spacing: 12) {
            if item.kind != .artist {
                ArtworkView(url: item.artworkUrl)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.subtitle.map { "\(item.displayKind) · \($0)" } ?? item.displayKind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
