import SwiftUI

struct AlbumContextMenuItems: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network

    let album: Album
    var artist: Artist? = nil

    var body: some View {
        Button {
            let tracks = musicLibrary.availableTracks(musicLibrary.tracksForAlbum(album.id), isOnline: network.isOnline)
            guard !tracks.isEmpty else { return }
            player.playNext(tracks: tracks, artworkURL: album.artworkUrl)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            let tracks = musicLibrary.availableTracks(musicLibrary.tracksForAlbum(album.id), isOnline: network.isOnline)
            guard !tracks.isEmpty else { return }
            player.addToEnd(tracks: tracks, artworkURL: album.artworkUrl)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        Divider()

        if musicLibrary.isAlbumFullyDownloaded(albumId: album.id) {
            Button(role: .destructive) {
                musicLibrary.markAlbumUndownloaded(albumId: album.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else {
            Button {
                guard let fullAlbum = musicLibrary.albumWithTracks(album.id) else { return }
                let resolvedArtist = artist ?? musicLibrary.artist(album.artistId)
                    ?? Artist(id: album.artistId, name: "", sortName: "", slug: "")
                downloadService.download(album: fullAlbum, artist: resolvedArtist)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}

struct TrackContextMenuItems: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    let track: Track
    var album: Album? = nil
    var artist: Artist? = nil

    private var artworkURL: URL? {
        album?.artworkUrl ?? track.album?.artworkUrl
    }

    private var isAvailable: Bool {
        network.isOnline || track.isDownloaded
    }

    var body: some View {
        if isAvailable {
            Button {
                player.playNext(tracks: [track], artworkURL: artworkURL)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                player.addToEnd(tracks: [track], artworkURL: artworkURL)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }

            Divider()
        }

        TrackDownloadMenuItems(track: track, album: album, artist: artist)
    }
}

struct ArtistContextMenuItems: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network

    let artist: Artist

    var body: some View {
        Button {
            let items = buildQueueItems()
            let available = musicLibrary.availableItems(items, isOnline: network.isOnline)
            guard !available.isEmpty else { return }
            player.playNext(queue: available)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            let items = buildQueueItems()
            let available = musicLibrary.availableItems(items, isOnline: network.isOnline)
            guard !available.isEmpty else { return }
            player.addToEnd(queue: available)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        Divider()

        if musicLibrary.isArtistFullyDownloaded(artistId: artist.id) {
            Button(role: .destructive) {
                musicLibrary.markArtistUndownloaded(artistId: artist.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else {
            Button {
                let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
                for album in albums {
                    downloadService.download(album: album, artist: artist)
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }

    private func buildQueueItems() -> [QueueItem] {
        musicLibrary.albumsWithTracksForArtist(artist.id).flatMap { album in
            (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
        }
    }
}

/// Isolated subview so download/offline observation doesn't invalidate the parent view.
struct TrackDownloadMenuItems: View {
    @Environment(DownloadService.self) private var downloadService
    @Environment(MusicLibrary.self) private var musicLibrary

    let track: Track
    var album: Album? = nil
    var artist: Artist? = nil

    var body: some View {
        if musicLibrary.isDownloaded(trackId: track.id) {
            Button(role: .destructive) {
                musicLibrary.markUndownloaded(trackId: track.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else if downloadService.isDownloading(trackId: track.id) {
            if let state = downloadService.activeDownloads[track.id], state.isPaused {
                Button {
                    downloadService.resumeDownload(trackId: track.id)
                } label: {
                    Label("Resume Download", systemImage: "play.circle")
                }
            } else {
                Button {
                    downloadService.pauseDownload(trackId: track.id)
                } label: {
                    Label("Pause Download", systemImage: "pause.circle")
                }
            }

            Button(role: .destructive) {
                downloadService.cancelDownload(trackId: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else if downloadService.isQueued(trackId: track.id) {
            Button(role: .destructive) {
                downloadService.cancelDownload(trackId: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else {
            Button {
                let resolvedAlbum = album ?? musicLibrary.album(track.albumId)
                guard let resolvedAlbum else { return }
                let albumArtist = artist ?? musicLibrary.artist(resolvedAlbum.artistId) ?? track.artist
                downloadService.download(track: track, album: resolvedAlbum, artist: albumArtist)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}
