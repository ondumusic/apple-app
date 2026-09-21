#if os(macOS)
import SwiftUI

struct AlbumDetailMac: View {
    let album: Album

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []

    /// Tall enough for the header's 180pt artwork plus its padding.
    static let headerHeight: CGFloat = 222

    private var sections: [TracksTableSection] {
        [TracksTableSection(id: album.id, album: album, tracks: tracks)]
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network,
                  downloadService: downloadService, artworkURL: album.artworkUrl)
    }

    private var hasMultipleArtists: Bool {
        Set(tracks.map(\.artist.id)).count > 1
    }


    var body: some View {
        VStack(spacing: 0) {
            // One scrolling section, and the table's interaction: the album header is
            // the table's own section header, so it scrolls with the rows while click
            // still selects and double-click plays, as on the artist page. No artwork
            // gutter — the header carries the cover, so the rows get the full width.
            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: hasMultipleArtists,
                showAlbum: false,
                isOffline: !network.isOnline,
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: hasMultipleArtists
                    ? DetailPageMetrics.trackRowHeightTwoLine
                    : DetailPageMetrics.trackRowHeight,
                embeddedStyle: true,
                sections: sections,
                groupLabels: TrackGrouping.discLabels(for: tracks),
                sectionHeader: { _ in
                    AnyView(
                        albumHeader
                            .environment(musicLibrary)
                            .environment(downloadService)
                            .environment(player)
                            .environment(network)
                    )
                },
                sectionHeaderIgnoresCellInset: true,
                sectionHeaderHeight: Self.headerHeight
            )
            .background(Color(NSColor.textBackgroundColor))
        }
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
        // The table paints its own background only as far as the cap, so the margin
        // beside it showed the window's grey. Page supplies the same surface.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
    }

    /// Artwork and metadata across the top, track list full width beneath — the shape
    /// Music.app uses for an album. The old layout kept the artwork in a left gutter
    /// spanning the first rows, which cost the columns 200pt at every width and got
    /// cramped fast in a narrow window. The artist page keeps that gutter for its
    /// per-album sections, where scrolling past several covers is the point.
    private var albumHeader: some View {
        HStack(alignment: .bottom, spacing: Spacing.page) {
            ArtworkView(url: album.artworkUrl)
                .frame(width: DetailPageMetrics.artworkSize, height: DetailPageMetrics.artworkSize)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(album.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                Text(album.artistName ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                DetailMetadataLine(parts: metadataParts)

                HStack(spacing: Spacing.related) {
                    PlayShuffleButtons(
                        accent: settings.resolvedAccentColor,
                        onPlay: { playAll(shuffle: false) },
                        onShuffle: { playAll(shuffle: true) },
                        isEnabled: !tracks.isEmpty
                    )
                    albumDownloadButton
                }
                .padding(.top, Spacing.related)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DetailPageMetrics.horizontalInset)
        .padding(.top, DetailPageMetrics.topInset)
        .padding(.bottom, DetailPageMetrics.bottomInset)
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let year = album.releaseYear { parts.append(String(year)) }
        parts.append(String(AttributedString(localized: "^[\(tracks.count) song](inflect: true)").characters))
        if totalDuration > 0 { parts.append(formattedTotalDuration(totalDuration)) }
        return parts
    }

    private var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    private var albumDownloadButton: some View {
        let isDownloading = downloadService.isAlbumDownloading(albumId: album.id)
        let isComplete = musicLibrary.isAlbumFullyDownloaded(albumId: album.id)
        return DownloadStateButton(
            state: isDownloading ? .downloading : (isComplete ? .downloaded : .notDownloaded),
            action: {
                if isDownloading {
                    downloadService.cancelAlbumDownloads(albumId: album.id)
                } else if isComplete {
                    DownloadRemovalRequest.post(
                        trackIds: Set(tracks.filter(\.isDownloaded).map(\.id)),
                        subject: album.name
                    )
                } else {
                    downloadAlbum()
                }
            },
            accent: settings.resolvedAccentColor
        )
    }

    private func reload() {
        tracks = musicLibrary.tracksForAlbum(album.id)
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay {
            player.playNow(tracks: queue, startingAt: queueIndex, artworkURL: album.artworkUrl)
        }
    }

    private func playAll(shuffle: Bool) {
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available, artworkURL: album.artworkUrl) }
        } else {
            player.requestPlay { player.playNow(tracks: available, artworkURL: album.artworkUrl) }
        }
    }

    private func downloadAlbum() {
        guard let fullAlbum = musicLibrary.albumWithTracks(album.id) else { return }
        let artist = musicLibrary.artist(album.artistId)
            ?? Artist(id: album.artistId, name: album.artistName ?? "", sortName: album.artistName ?? "", slug: "")
        downloadService.download(album: fullAlbum, artist: artist)
    }
}
#endif
