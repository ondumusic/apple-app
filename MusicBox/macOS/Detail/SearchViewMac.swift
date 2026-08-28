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
    @State private var displayedQuery: String = ""
    @State private var trackSelection: Set<UUID> = []

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
                displayedQuery = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = musicLibrary.search(query)
            displayedQuery = query
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !results.artists.isEmpty || !results.albums.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !results.artists.isEmpty { artistsSection }
                        if !results.albums.isEmpty { albumsSection }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                Divider()
            }
            if !results.tracks.isEmpty {
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
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Artists").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(results.artists.prefix(10)) { artist in
                        Button {
                            NotificationCenter.default.post(name: .navigateToArtist, object: artist)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "music.mic")
                                    .font(.title2)
                                    .frame(width: 60, height: 60)
                                    .background(.quaternary, in: Circle())
                                Text(artist.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 80)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Albums").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(results.albums.prefix(10)) { album in
                        Button {
                            NotificationCenter.default.post(name: .navigateToAlbum, object: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ArtworkView(url: album.artworkUrl)
                                    .frame(width: 96, height: 96)
                                Text(album.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 96, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
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
