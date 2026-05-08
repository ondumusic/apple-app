#if os(macOS)
import SwiftUI

struct ArtistDetailMac: View {
    let artist: Artist

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @State private var albums: [Album] = []
    /// Selection is hoisted up to the artist level so the single TracksTable can carry
    /// it across all album sections (cmd-click + shift-range work natively).
    @State private var selection: Set<UUID> = []

    private var totalSongs: Int {
        albums.reduce(0) { $0 + ($1.tracks?.count ?? 0) }
    }

    /// Flat concatenation of every album's tracks in display order. Selection indexes
    /// and onPlay indexes refer to this array.
    private var allTracks: [Track] {
        albums.flatMap { $0.tracks ?? [] }
    }

    private var sections: [TracksTableSection] {
        albums.map { TracksTableSection(id: $0.id, album: $0, tracks: $0.tracks ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)
            TracksTable(
                tracks: allTracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: false,
                showAlbum: false,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: 40,
                embeddedStyle: true,
                sections: sections,
                sectionHeader: { album in
                    AnyView(AlbumSectionHeader(
                        album: album,
                        onPlay: { playAlbum(album, shuffle: false) },
                        onShuffle: { playAlbum(album, shuffle: true) }
                    ))
                },
                sectionHeaderHeight: 84
            )
        }
        .background(Color(NSColor.textBackgroundColor))
        .navigationTitle(artist.name)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) { reload() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.largeTitle.bold())
                Text("^[\(albums.count) album](inflect: true) • ^[\(totalSongs) song](inflect: true)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { playAll(shuffle: false) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(albums.isEmpty)
                Button { playAll(shuffle: true) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .disabled(albums.isEmpty)
            }
            .controlSize(.large)
        }
    }

    private var trackActions: TrackActions {
        // Album-specific artwork URL is supplied per call inside playTrack/playAlbum;
        // generic actions fall back to no artwork — fine for context-menu-driven playback.
        .standard(player: player, musicLibrary: musicLibrary, network: network, artworkURL: nil)
    }

    private func reload() {
        albums = musicLibrary.albumsWithTracksForArtist(artist.id)
    }

    private func playTrack(at index: Int) {
        guard allTracks.indices.contains(index) else { return }
        let target = allTracks[index]
        let available = musicLibrary.availableTracks(allTracks, isOnline: network.isOnline)
        guard let queueIndex = available.firstIndex(where: { $0.id == target.id }) else { return }
        let artwork = albums.first { $0.id == target.albumId }?.artworkUrl
        player.requestPlay {
            player.playNow(tracks: available, startingAt: queueIndex, artworkURL: artwork)
        }
    }

    private func playAll(shuffle: Bool) {
        let allItems = albums.flatMap { album in
            (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
        }
        let items = musicLibrary.availableItems(allItems, isOnline: network.isOnline)
        guard !items.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(queue: items) }
        } else {
            player.requestPlay { player.playNow(queue: items) }
        }
    }

    private func playAlbum(_ album: Album, shuffle: Bool) {
        let tracks = album.tracks ?? []
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available, artworkURL: album.artworkUrl) }
        } else {
            player.requestPlay { player.playNow(tracks: available, artworkURL: album.artworkUrl) }
        }
    }
}

private struct AlbumSectionHeader: View {
    let album: Album
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(value: album) {
                ArtworkView(url: album.artworkUrl)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = album.releaseYear {
                        Text(String(year))
                    }
                    Text("•").foregroundStyle(.tertiary)
                    Text("^[\(album.tracks?.count ?? 0) song](inflect: true)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button { onPlay() } label: { Image(systemName: "play.fill") }
                Button { onShuffle() } label: { Image(systemName: "shuffle") }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
#endif
