#if os(macOS)
import SwiftUI

struct ArtistDetailMac: View {
    let artist: Artist

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    @State private var albums: [Album] = []

    private var totalSongs: Int {
        albums.reduce(0) { $0 + ($1.tracks?.count ?? 0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                ForEach(albums) { album in
                    AlbumInlineSection(album: album, artist: artist)
                    if album.id != albums.last?.id {
                        Divider()
                    }
                }
            }
            .padding(20)
        }
        // Use the content/text backdrop (white in light, ~near-black in dark) instead
        // of `.background` (which resolves to windowBackgroundColor — that's the grey
        // tint we don't want under the embedded track tables).
        .background(Color(NSColor.textBackgroundColor))
        .defaultScrollAnchor(.top)
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

    private func reload() {
        albums = musicLibrary.albumsWithTracksForArtist(artist.id)
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
}

private struct AlbumInlineSection: View {
    let album: Album
    let artist: Artist

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    /// Per-section selection state. Multi-select within an album works; cross-album
    /// selection isn't supported yet (each section is its own NSTableView).
    @State private var selection: Set<UUID> = []

    private var tracks: [Track] { album.tracks ?? [] }
    private var hasMultipleArtists: Bool { Set(tracks.map(\.artist.id)).count > 1 }
    /// Each row's height in the embedded table. Tall enough to fit a 2-line wrapped
    /// title and an optional artist subline (shown when the album has tracks from
    /// multiple artists).
    private let rowHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        Text("^[\(tracks.count) song](inflect: true)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Button { playAlbum(shuffle: false) } label: { Image(systemName: "play.fill") }
                    Button { playAlbum(shuffle: true) } label: { Image(systemName: "shuffle") }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: hasMultipleArtists,
                showAlbum: false,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: rowHeight,
                embeddedStyle: true
            )
            .frame(height: tableHeight)
        }
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network, artworkURL: album.artworkUrl)
    }

    /// Sized to fit content so the outer ScrollView is the only scroller. +6 for the
    /// inset listStyle's natural top/bottom padding.
    private var tableHeight: CGFloat {
        max(rowHeight, CGFloat(tracks.count) * rowHeight + 6)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = available.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay {
            player.playNow(tracks: available, startingAt: queueIndex, artworkURL: album.artworkUrl)
        }
    }

    private func playAlbum(shuffle: Bool) {
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available, artworkURL: album.artworkUrl) }
        } else {
            player.requestPlay { player.playNow(tracks: available, artworkURL: album.artworkUrl) }
        }
    }
}
#endif
