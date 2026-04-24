import SwiftUI

struct AlbumContextMenuItems: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(PlaylistController.self) private var playlistController
    @Environment(NetworkMonitor.self) private var network

    let album: Album
    var artist: Artist? = nil
    var downloadedOnly: Bool = false

    private var lastUsedPlaylist: Playlist? {
        guard let id = playlistController.lastUsedPlaylistId else { return nil }
        return musicLibrary.playlist(id)
    }

    private func availableTracks() -> [Track] {
        musicLibrary.availableTracks(musicLibrary.tracksForAlbum(album.id), isOnline: network.isOnline)
    }

    /// All tracks on this album regardless of online availability — used for playlist adds.
    private func allTracks() -> [Track] {
        musicLibrary.tracksForAlbum(album.id)
    }

    var body: some View {
        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.requestPlay { player.playNow(tracks: tracks, artworkURL: album.artworkUrl) }
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.requestPlay { player.playShuffled(tracks: tracks, artworkURL: album.artworkUrl) }
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }

        Divider()

        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.playNext(tracks: tracks, artworkURL: album.artworkUrl)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.addToEnd(tracks: tracks, artworkURL: album.artworkUrl)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        if let last = lastUsedPlaylist {
            Button {
                let ids = allTracks().map(\.id)
                guard !ids.isEmpty else { return }
                playlistController.addTracks(ids, to: last.id)
            } label: {
                Label("Add to \(last.name)", systemImage: "plus.circle")
            }
        }

        Button {
            let ids = allTracks().map(\.id)
            guard !ids.isEmpty else { return }
            NotificationCenter.default.post(name: .requestAddToPlaylist, object: ids)
        } label: {
            Label("Add to Playlist…", systemImage: "music.note.list")
        }

        Divider()

        if downloadedOnly || musicLibrary.isAlbumFullyDownloaded(albumId: album.id) {
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
    @Environment(PlaylistController.self) private var playlistController
    @Environment(NetworkMonitor.self) private var network

    let track: Track
    var album: Album? = nil
    var artist: Artist? = nil

    private var artworkURL: URL? {
        album?.artworkUrl ?? track.album?.artworkUrl
    }

    private var lastUsedPlaylist: Playlist? {
        guard let id = playlistController.lastUsedPlaylistId else { return nil }
        return musicLibrary.playlist(id)
    }

    private var isAvailable: Bool {
        network.isOnline || track.isDownloaded
    }

    /// Tracks from this track through end of album (for "Play" action).
    private func tracksFromHere() -> [Track] {
        let albumId = album?.id ?? track.albumId
        let albumTracks = musicLibrary.availableTracks(
            musicLibrary.tracksForAlbum(albumId), isOnline: network.isOnline
        )
        guard let startIndex = albumTracks.firstIndex(where: { $0.id == track.id }) else {
            return [track]
        }
        return Array(albumTracks[startIndex...])
    }

    var body: some View {
        if isAvailable {
            Button {
                let tracks = tracksFromHere()
                guard !tracks.isEmpty else { return }
                player.requestPlay { player.playNow(tracks: tracks, artworkURL: artworkURL) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

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

            if let last = lastUsedPlaylist {
                Button {
                    playlistController.addTrack(track.id, to: last.id)
                } label: {
                    Label("Add to \(last.name)", systemImage: "plus.circle")
                }
            }

            Button {
                NotificationCenter.default.post(name: .requestAddToPlaylist, object: [track.id])
            } label: {
                Label("Add to Playlist…", systemImage: "music.note.list")
            }

            Divider()

            Button {
                let target = artist ?? track.artist
                NotificationCenter.default.post(name: .navigateToArtist, object: target)
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }

            if let resolvedAlbum = album ?? musicLibrary.album(track.albumId) {
                Button {
                    NotificationCenter.default.post(name: .navigateToAlbum, object: resolvedAlbum)
                } label: {
                    Label("Go to Album", systemImage: "square.stack")
                }
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
    @Environment(PlaylistController.self) private var playlistController
    @Environment(NetworkMonitor.self) private var network

    let artist: Artist
    var downloadedOnly: Bool = false

    private var lastUsedPlaylist: Playlist? {
        guard let id = playlistController.lastUsedPlaylistId else { return nil }
        return musicLibrary.playlist(id)
    }

    private func availableItems() -> [QueueItem] {
        let items = buildQueueItems()
        return musicLibrary.availableItems(items, isOnline: network.isOnline)
    }

    var body: some View {
        Button {
            let available = availableItems()
            guard !available.isEmpty else { return }
            player.requestPlay { player.playNow(queue: available) }
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            let available = availableItems()
            guard !available.isEmpty else { return }
            player.requestPlay { player.playShuffled(queue: available) }
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }

        Divider()

        Button {
            let available = availableItems()
            guard !available.isEmpty else { return }
            player.playNext(queue: available)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            let available = availableItems()
            guard !available.isEmpty else { return }
            player.addToEnd(queue: available)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        if let last = lastUsedPlaylist {
            Button {
                let ids = buildQueueItems().map(\.track.id)
                guard !ids.isEmpty else { return }
                playlistController.addTracks(ids, to: last.id)
            } label: {
                Label("Add to \(last.name)", systemImage: "plus.circle")
            }
        }

        Button {
            let ids = buildQueueItems().map(\.track.id)
            guard !ids.isEmpty else { return }
            NotificationCenter.default.post(name: .requestAddToPlaylist, object: ids)
        } label: {
            Label("Add to Playlist…", systemImage: "music.note.list")
        }

        Divider()

        if downloadedOnly || musicLibrary.isArtistFullyDownloaded(artistId: artist.id) {
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
