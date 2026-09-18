#if os(macOS)
import SwiftUI

/// Context menu for a multi-album selection. The single-album menu carries per-album
/// state (download vs remove, the artist to attribute a download to) that doesn't
/// generalise across a mixed selection, so this offers only what's unambiguous for a set.
struct AlbumsContextMenuItems: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(PlaylistController.self) private var playlistController
    @Environment(NetworkMonitor.self) private var network

    let albums: [Album]

    private func allTracks() -> [Track] {
        albums.flatMap { musicLibrary.tracksForAlbum($0.id) }
    }

    private func availableTracks() -> [Track] {
        musicLibrary.availableTracks(allTracks(), isOnline: network.isOnline)
    }

    private var lastUsedPlaylist: Playlist? {
        guard let id = playlistController.lastUsedPlaylistId else { return nil }
        return musicLibrary.playlist(id)
    }

    var body: some View {
        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.requestPlay { player.playNow(tracks: tracks, artworkURL: albums.first?.artworkUrl) }
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.requestPlay { player.playShuffled(tracks: tracks, artworkURL: albums.first?.artworkUrl) }
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }

        Divider()

        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.playNext(tracks: tracks, artworkURL: albums.first?.artworkUrl)
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            let tracks = availableTracks()
            guard !tracks.isEmpty else { return }
            player.addToEnd(tracks: tracks, artworkURL: albums.first?.artworkUrl)
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

        Button {
            for album in albums {
                guard let full = musicLibrary.albumWithTracks(album.id) else { continue }
                let artist = musicLibrary.artist(album.artistId)
                    ?? Artist(id: album.artistId, name: "", sortName: "", slug: "")
                downloadService.download(album: full, artist: artist)
            }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }

        let downloaded = albums.flatMap {
            musicLibrary.tracksForAlbum($0.id).filter(\.isDownloaded).map(\.id)
        }
        if !downloaded.isEmpty {
            Button(role: .destructive) {
                let subject = String(
                    AttributedString(localized: "^[\(albums.count) album](inflect: true)").characters
                )
                DownloadRemovalRequest.post(trackIds: Set(downloaded), subject: subject)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }
}
#endif
