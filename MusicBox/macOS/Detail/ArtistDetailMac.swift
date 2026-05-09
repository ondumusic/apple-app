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
                sectionHeaderHeight: 80,
                artwork: { album in
                    AnyView(AlbumArtworkOverlay(album: album))
                },
                artworkSize: 160,
                artworkInset: 20
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

/// Right-side metadata for an album section: title, year, play/shuffle buttons. The
/// album artwork is drawn separately as a left-edge overlay (`AlbumArtworkOverlay`)
/// over multiple track rows — iTunes-style split layout.
private struct AlbumSectionHeader: View {
    let album: Album
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                if let year = album.releaseYear {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { onPlay() } label: { Label("Play", systemImage: "play.fill") }
                Button { onShuffle() } label: { Label("Shuffle", systemImage: "shuffle") }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        // Push past the spacer column (artworkSize 160 + 2 × inset 20 = 200) AND past
        // the number column (36) plus the title cell's leading text inset (4) — so the
        // album title sits in the same x position as the track titles below.
        .padding(.leading, 240)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
    }
}

/// Album artwork rendered in the leftmost spacer-column area of TracksTable. Sized
/// to match `artworkSize` × `artworkSize`; positioned by the table to anchor at the
/// section's header row and extend down across the first few track rows.
private struct AlbumArtworkOverlay: View {
    let album: Album

    private var trackCount: Int { album.tracks?.count ?? 0 }
    private var totalDuration: TimeInterval {
        album.tracks?.reduce(0) { $0 + $1.duration } ?? 0
    }
    private var formattedDuration: String {
        let totalMinutes = Int((totalDuration / 60).rounded())
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return mins == 0 ? "\(hours) hr" : "\(hours) hr \(mins) min"
        }
        return "\(max(1, totalMinutes)) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: album) {
                ArtworkView(url: album.artworkUrl)
                    .frame(width: 160, height: 160)
            }
            .buttonStyle(.plain)
            Text("^[\(trackCount) song](inflect: true), \(formattedDuration)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
        }
    }
}
#endif
