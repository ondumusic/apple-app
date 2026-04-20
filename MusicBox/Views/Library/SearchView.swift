import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SearchView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(SearchHistory.self) private var searchHistory
    @Environment(NetworkMonitor.self) private var network

    let query: String
    @Binding var path: NavigationPath

    @State private var results: (artists: [Artist], albums: [Album], tracks: [Track]) = ([], [], [])
    @State private var didAddToHistory = false

    var body: some View {
        let hasResults = !results.artists.isEmpty || !results.albums.isEmpty || !results.tracks.isEmpty

        Group {
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
        .onChange(of: query) {
            didAddToHistory = false
            results = query.isEmpty ? ([], [], []) : musicLibrary.search(query)
        }
        .task(id: musicLibrary.revision) {
            guard !query.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = musicLibrary.search(query)
        }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &results.tracks)
        }
    }

    // MARK: - Results

    private func resultsList(_ results: (artists: [Artist], albums: [Album], tracks: [Track])) -> some View {
        List {
            if !results.artists.isEmpty {
                Section("Artists") {
                    ForEach(results.artists.prefix(5)) { artist in
                        artistRow(artist)
                    }
                }
            }

            if !results.albums.isEmpty {
                Section("Albums") {
                    ForEach(results.albums.prefix(5)) { album in
                        albumRow(album)
                    }
                }
            }

            if !results.tracks.isEmpty {
                Section("Songs") {
                    ForEach(results.tracks.prefix(10)) { track in
                        trackRow(track, allTracks: results.tracks)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
                .task {
                    if !didAddToHistory, results.artists.contains(where: { $0.id == artist.id }) {
                        didAddToHistory = true
                        searchHistory.add(SearchHistoryItem(
                            id: artist.id, kind: .artist, name: artist.name
                        ))
                    }
                }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
                .task {
                    if !didAddToHistory, results.albums.contains(where: { $0.id == album.id }) {
                        didAddToHistory = true
                        searchHistory.add(SearchHistoryItem(
                            id: album.id, kind: .album, name: album.name,
                            subtitle: album.artistName, artworkUrl: album.artworkUrl,
                            artistId: album.artistId
                        ))
                    }
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
                artistRow(artist)
            }
        case .album:
            if let album = musicLibrary.album(item.id) {
                albumRow(album)
            }
        case .song:
            if let track = musicLibrary.track(item.id) {
                trackRow(track, allTracks: [track])
            }
        }
    }

    // MARK: - Shared row views

    private func artistRow(_ artist: Artist) -> some View {
        Button {
            dismissKeyboard()
            path.append(artist)
        } label: {
            ArtistCard(artist: artist)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            ArtistContextMenuItems(artist: artist)
        }
    }

    private func albumRow(_ album: Album) -> some View {
        Button {
            dismissKeyboard()
            path.append(album)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(url: album.artworkUrl)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .lineLimit(1)
                    if let artistName = album.artistName {
                        Text(artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let year = album.releaseYear {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            AlbumContextMenuItems(album: album)
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func trackRow(_ track: Track, allTracks: [Track]) -> some View {
        TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
            let allItems = allTracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
            let items = musicLibrary.availableItems(allItems, isOnline: network.isOnline)
            if let idx = items.firstIndex(where: { $0.track.id == track.id }) {
                player.requestPlay { player.playNow(queue: items, startingAt: idx) }
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
