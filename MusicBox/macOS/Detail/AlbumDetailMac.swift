#if os(macOS)
import SwiftUI

struct AlbumDetailMac: View {
    let album: Album
    /// Set when this view is pushed rather than shown as a section's root. The toolbar's
    /// own back button sits beside the transport controls where it reads as a player
    /// control, so pushed detail views carry their own next to the title.
    var showsBackButton = false

    @Environment(\.dismiss) private var dismiss
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []

    private var hasMultipleArtists: Bool {
        Set(tracks.map(\.artist.id)).count > 1
    }

    private var trackActions: TrackActions {
        .standard(player: player, musicLibrary: musicLibrary, network: network, downloadService: downloadService, artworkURL: album.artworkUrl)
    }

    /// Single-section view of this album — same iTunes split layout as ArtistDetailMac
    /// uses for each of an artist's albums. Album metadata + buttons live in the
    /// section header; artwork is overlaid on the left.
    private var sections: [TracksTableSection] {
        [TracksTableSection(id: album.id, album: albumWithLoadedTracks, tracks: tracks)]
    }

    /// `album` from the navigation destination doesn't have `.tracks` populated —
    /// rebuild a copy with the loaded tracks so the artwork overlay's caption
    /// (track count, total duration) is accurate.
    private var albumWithLoadedTracks: Album {
        var copy = album
        copy.tracks = tracks
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsBackButton {
                HStack {
                    BackToResultsButton()
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                Divider()
            }
            table
        }
        .navigationBarBackButtonHidden(showsBackButton)
    }

    private var table: some View {
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
            sectionHeader: { sectionAlbum in
                AnyView(
                    AlbumSectionHeader(
                        album: sectionAlbum,
                        onPlay: { playAll(shuffle: false) },
                        onShuffle: { playAll(shuffle: true) },
                        onDownload: { downloadAlbum() },
                        onCancelDownload: { downloadService.cancelAlbumDownloads(albumId: album.id) }
                    )
                    .environment(musicLibrary)
                    .environment(downloadService)
                )
            },
            sectionHeaderHeight: 80,
            artwork: { sectionAlbum in
                AnyView(AlbumArtworkOverlay(album: sectionAlbum))
            },
            artworkSize: 160,
            artworkInset: 20
        )
        .background(Color(NSColor.textBackgroundColor))
        .navigationTitle(album.name)
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
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
