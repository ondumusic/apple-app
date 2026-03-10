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

        if musicLibrary.downloadedTrackCount(albumId: album.id) == musicLibrary.tracksForAlbum(album.id).count
            && musicLibrary.tracksForAlbum(album.id).count > 0 {
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

        if musicLibrary.isArtistDownloaded(artistId: artist.id) {
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
