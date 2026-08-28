#if os(macOS)
import SwiftUI

struct ArtistDetailMac: View {
    let artist: Artist

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

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
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: 40,
                embeddedStyle: true,
                sections: sections,
                sectionHeader: { album in
                    AnyView(
                        AlbumSectionHeader(
                            album: album,
                            onPlay: { playAlbum(album, shuffle: false) },
                            onShuffle: { playAlbum(album, shuffle: true) },
                            onDownload: { downloadAlbum(album) },
                            onCancelDownload: { cancelAlbumDownload(album) }
                        )
                        // Inject services so the header can reflect download state live —
                        // NSHostingView creates its own environment scope, so we need to
                        // pass these explicitly.
                        .environment(musicLibrary)
                        .environment(downloadService)
                    )
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
                    Image(systemName: "play.fill")
                }
                .disabled(albums.isEmpty)
                Button { playAll(shuffle: true) } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(albums.isEmpty)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
    }

    private var trackActions: TrackActions {
        // Album-specific artwork URL is supplied per call inside playTrack/playAlbum;
        // generic actions fall back to no artwork — fine for context-menu-driven playback.
        .standard(player: player, musicLibrary: musicLibrary, network: network, downloadService: downloadService)
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

    private func downloadAlbum(_ album: Album) {
        guard let fullAlbum = musicLibrary.albumWithTracks(album.id) else { return }
        let albumArtist = musicLibrary.artist(album.artistId)
            ?? Artist(id: album.artistId, name: artist.name, sortName: artist.sortName, slug: artist.slug)
        downloadService.download(album: fullAlbum, artist: albumArtist)
    }

    private func cancelAlbumDownload(_ album: Album) {
        downloadService.cancelAlbumDownloads(albumId: album.id)
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

#endif
