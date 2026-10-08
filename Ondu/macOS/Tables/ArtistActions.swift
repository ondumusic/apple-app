#if os(macOS)
import Foundation

/// Actions the artist list can invoke, mirroring `TrackActions` so the AppKit table
/// doesn't have to reach back into SwiftUI's environment from a non-SwiftUI context.
@MainActor
struct ArtistActions {
    var play: (Artist) -> Void = { _ in }
    var shuffle: (Artist) -> Void = { _ in }
    var playNext: (Artist) -> Void = { _ in }
    var addToEnd: (Artist) -> Void = { _ in }
    var addToPlaylist: (Artist) -> Void = { _ in }
    var download: (Artist) -> Void = { _ in }
    var removeDownload: (Artist) -> Void = { _ in }
    var isFullyDownloaded: (Artist) -> Bool = { _ in false }
    var supportsDownload: Bool = false
    var chooseArtwork: (Artist) -> Void = { _ in }
    var removeArtwork: (Artist) -> Void = { _ in }
    /// Only offered where artwork is on show: actions for pictures you can't see would be
    /// a strange thing to find in a list of names.
    var supportsArtwork: Bool = false

    static func standard(
        player: PlayerService,
        musicLibrary: MusicLibrary,
        network: NetworkMonitor,
        downloadService: DownloadService? = nil
    ) -> ArtistActions {
        func items(_ artist: Artist) -> [QueueItem] {
            let all = musicLibrary.albumsWithTracksForArtist(artist.id).flatMap { album in
                (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
            }
            return musicLibrary.availableItems(all, isOnline: network.isOnline)
        }

        var a = ArtistActions()
        a.play = { artist in
            let available = items(artist)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playNow(queue: available) }
        }
        a.shuffle = { artist in
            let available = items(artist)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playShuffled(queue: available) }
        }
        a.playNext = { artist in
            let available = items(artist)
            guard !available.isEmpty else { return }
            player.playNext(queue: available)
        }
        a.addToEnd = { artist in
            let available = items(artist)
            guard !available.isEmpty else { return }
            player.addToEnd(queue: available)
        }
        a.addToPlaylist = { artist in
            let ids = musicLibrary.albumsWithTracksForArtist(artist.id)
                .flatMap { ($0.tracks ?? []).map(\.id) }
            guard !ids.isEmpty else { return }
            NotificationCenter.default.post(name: .requestAddToPlaylist, object: ids)
        }
        a.isFullyDownloaded = { musicLibrary.isArtistFullyDownloaded(artistId: $0.id) }
        if let downloadService {
            a.supportsDownload = true
            a.download = { artist in
                for album in musicLibrary.albumsWithTracksForArtist(artist.id) {
                    downloadService.download(album: album, artist: artist)
                }
            }
            a.removeDownload = { artist in
                let ids = Set(musicLibrary.downloadedTracks()
                    .filter { $0.albumArtistId == artist.id }.map(\.id))
                DownloadRemovalRequest.post(trackIds: ids, subject: artist.name)
            }
        }
        return a
    }
}
#endif
