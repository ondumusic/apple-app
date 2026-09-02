#if os(macOS)
import SwiftUI

struct AlbumDetailMac: View {
    let album: Album
    /// Set when this view is pushed rather than shown as a section's root. The toolbar's
    /// own back button sits beside the transport controls where it reads as a player
    /// control, so pushed detail views carry their own next to the title.
    var backDestination: String?

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
            if let backDestination { BackBar(destination: backDestination) }
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
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: 40,
                embeddedStyle: true,
                sections: sections,
                sectionHeader: { _ in
                    AnyView(
                        albumHeader
                            .environment(musicLibrary)
                            .environment(downloadService)
                            .environment(player)
                            .environment(network)
                    )
                },
                sectionHeaderHeight: Self.headerHeight
            )
            .background(Color(NSColor.textBackgroundColor))
        }
        .navigationTitle(album.name)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
        // The table paints its own background only as far as the cap, so the margin
        // beside it showed the window's grey. Page supplies the same surface.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .navigationBarBackButtonHidden(backDestination != nil)
    }

    /// Artwork and metadata across the top, track list full width beneath — the shape
    /// Music.app uses for an album. The old layout kept the artwork in a left gutter
    /// spanning the first rows, which cost the columns 200pt at every width and got
    /// cramped fast in a narrow window. The artist page keeps that gutter for its
    /// per-album sections, where scrolling past several covers is the point.
    private var albumHeader: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ArtworkView(url: album.artworkUrl)
                .frame(width: 180, height: 180)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(album.name)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                Text(album.artistName ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = album.releaseYear {
                        Text(String(year))
                        Text("·")
                    }
                    Text("^[\(tracks.count) song](inflect: true)")
                    if totalDuration > 0 {
                        Text("·")
                        Text(formattedTotalDuration(totalDuration))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button { playAll(shuffle: false) } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    Button { playAll(shuffle: true) } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    albumDownloadButton
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    @ViewBuilder
    private var albumDownloadButton: some View {
        let isDownloading = downloadService.isAlbumDownloading(albumId: album.id)
        let isComplete = musicLibrary.isAlbumFullyDownloaded(albumId: album.id)
        Button {
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
        } label: {
            if isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: isComplete ? "arrow.down.circle.fill" : "arrow.down.circle")
            }
        }
        .help(isComplete ? "Remove Download" : (isDownloading ? "Cancel Download" : "Download"))
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
