#if os(macOS)
import AppKit
import Foundation

/// What the queue table can do, in the index space it actually works in.
///
/// Every position here is an offset into up-next — 0 is "plays next" — which is what
/// PlayerService's queue mutations take. `upNextEntries` reports indices into the whole
/// queue instead, and passing those where these belong is a bug this code has had three
/// times: the reorder, the per-row remove, and double-click while shuffled.
@MainActor
struct QueueActions {
    var play: (Int) -> Void = { _ in }
    var remove: (IndexSet) -> Void = { _ in }
    var move: (IndexSet, Int) -> Void = { _, _ in }
    var insertTracks: ([UUID], Int) -> Void = { _, _ in }
    var insertAlbums: ([UUID], Int) -> Void = { _, _ in }
    var insertArtists: ([UUID], Int) -> Void = { _, _ in }
    var addToPlaylist: ([UUID]) -> Void = { _ in }
    var insertPlaylists: ([UUID], Int) -> Void = { _, _ in }
    /// Both the rows and the tracks they hold, because the two scopes mean different
    /// things by it: in Up Next these move a row that's already queued, in History they
    /// queue a copy of something that has already played.
    var playNext: (IndexSet, [Track]) -> Void = { _, _ in }
    var playLast: (IndexSet, [Track]) -> Void = { _, _ in }
    var goToAlbum: (Track) -> Void = { _ in }
    var goToArtist: (Track) -> Void = { _ in }

    static func standard(player: PlayerService, musicLibrary: MusicLibrary, network: NetworkMonitor) -> QueueActions {
        var a = QueueActions()
        a.goToAlbum = navigateToAlbum(musicLibrary)
        a.goToArtist = navigateToArtist(musicLibrary)
        a.play = { position in
            player.skipTo(queueIndex: player.currentIndex + 1 + position)
        }
        a.remove = { positions in
            player.removeFromQueue(at: positions)
        }
        a.move = { positions, destination in
            player.moveQueueItems(from: positions, to: destination)
        }
        a.insertTracks = { trackIds, position in
            let tracks = trackIds.compactMap { musicLibrary.track($0) }
            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
            guard !available.isEmpty else { return }
            player.insertIntoQueue(
                available.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) },
                at: position
            )
        }
        a.insertAlbums = { albumIds, position in
            let items = albumIds.flatMap { albumId -> [QueueItem] in
                let tracks = musicLibrary.tracksForAlbum(albumId)
                let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                return available.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
            }
            guard !items.isEmpty else { return }
            player.insertIntoQueue(items, at: position)
        }
        a.insertArtists = { artistIds, position in
            let items = artistIds.flatMap { artistId -> [QueueItem] in
                musicLibrary.albumsWithTracksForArtist(artistId).flatMap { album -> [QueueItem] in
                    let tracks = musicLibrary.tracksForAlbum(album.id)
                    return musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                        .map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                }
            }
            guard !items.isEmpty else { return }
            player.insertIntoQueue(items, at: position)
        }
        a.insertPlaylists = { playlistIds, position in
            let items = playlistIds.flatMap { playlistId -> [QueueItem] in
                let tracks = musicLibrary.tracksForPlaylist(playlistId)
                return musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                    .map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
            }
            guard !items.isEmpty else { return }
            player.insertIntoQueue(items, at: position)
        }
        a.playNext = { positions, _ in
            player.moveQueueItems(from: positions, to: 0)
        }
        a.playLast = { positions, _ in
            player.moveQueueItems(from: positions, to: player.upNextEntries.count)
        }
        a.addToPlaylist = { trackIds in
            guard !trackIds.isEmpty else { return }
            NotificationCenter.default.post(name: .requestAddToPlaylist, object: trackIds)
        }
        return a
    }

    /// History is read-only: the only thing a row does is take you back to it. Positions
    /// here count backwards from the current track, 0 being what played last — which is
    /// the order `historyEntries` reports.
    static func history(player: PlayerService, musicLibrary: MusicLibrary) -> QueueActions {
        var a = QueueActions()
        a.goToAlbum = navigateToAlbum(musicLibrary)
        a.goToArtist = navigateToArtist(musicLibrary)
        a.play = { position in
            player.skipTo(queueIndex: player.currentIndex - 1 - position)
        }
        a.playNext = { _, tracks in
            player.insertIntoQueue(tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }, at: 0)
        }
        a.playLast = { _, tracks in
            player.insertIntoQueue(
                tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) },
                at: player.upNextEntries.count
            )
        }
        a.addToPlaylist = { trackIds in
            guard !trackIds.isEmpty else { return }
            NotificationCenter.default.post(name: .requestAddToPlaylist, object: trackIds)
        }
        return a
    }
}

@MainActor
private func navigateToAlbum(_ musicLibrary: MusicLibrary) -> (Track) -> Void {
    { track in
        guard let album = musicLibrary.albumWithTracks(track.albumId) else { return }
        MainWindowNavigation.request(.navigateToAlbum, object: album)
    }
}

/// The album artist, not the track's own — a featuring credit isn't in the Artists list
/// and wouldn't resolve.
@MainActor
private func navigateToArtist(_ musicLibrary: MusicLibrary) -> (Track) -> Void {
    { track in
        guard let artist = musicLibrary.artist(track.albumArtistId) else { return }
        MainWindowNavigation.request(.navigateToArtist, object: artist)
    }
}

extension NSPasteboard.PasteboardType {
    /// Rows being dragged within the queue, carrying their up-next positions. Distinct
    /// from the library types so a reorder can't be mistaken for an insert.
    static let musicBoxQueueRows = NSPasteboard.PasteboardType("com.musicbox.queue.rows")
}
#endif
