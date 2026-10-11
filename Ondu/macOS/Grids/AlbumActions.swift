#if os(macOS)
import Foundation

/// Actions the album grid can invoke, mirroring `ArtistActions` so the AppKit grid
/// doesn't have to reach back into SwiftUI's environment from a non-SwiftUI context.
/// Every action takes a set rather than one album: the grid is multi-select, and a
/// single-album menu is just the one-element case.
@MainActor
struct AlbumActions {
    var play: ([Album]) -> Void = { _ in }
    var shuffle: ([Album]) -> Void = { _ in }
    var playNext: ([Album]) -> Void = { _ in }
    var addToEnd: ([Album]) -> Void = { _ in }
    var addToPlaylist: ([Album]) -> Void = { _ in }
    var download: ([Album]) -> Void = { _ in }
    var removeDownload: ([Album]) -> Void = { _ in }
    var isFullyDownloaded: ([Album]) -> Bool = { _ in false }
    var supportsDownload: Bool = false

    static func standard(
        player: PlayerService,
        musicLibrary: MusicLibrary,
        network: NetworkMonitor,
        downloadService: DownloadService? = nil
    ) -> AlbumActions {
        func items(_ albums: [Album]) -> [QueueItem] {
            let all = albums.flatMap { album in
                musicLibrary.tracksForAlbum(album.id).map {
                    QueueItem(track: $0, artworkURL: album.artworkUrl)
                }
            }
            return musicLibrary.availableItems(all, isOnline: network.isOnline)
        }

        var a = AlbumActions()
        a.play = { albums in
            let available = items(albums)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playNow(queue: available) }
        }
        a.shuffle = { albums in
            let available = items(albums)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playShuffled(queue: available) }
        }
        a.playNext = { albums in
            let available = items(albums)
            guard !available.isEmpty else { return }
            player.playNext(queue: available)
        }
        a.addToEnd = { albums in
            let available = items(albums)
            guard !available.isEmpty else { return }
            player.addToEnd(queue: available)
        }
        a.addToPlaylist = { albums in
            let ids = albums.flatMap { musicLibrary.tracksForAlbum($0.id).map(\.id) }
            guard !ids.isEmpty else { return }
            NotificationCenter.default.post(name: .requestAddToPlaylist, object: ids)
        }
        // Every album in the selection, so a mixed selection offers Download rather than
        // claiming the whole thing is already on disk.
        a.isFullyDownloaded = { albums in
            !albums.isEmpty && albums.allSatisfy { musicLibrary.isAlbumFullyDownloaded(albumId: $0.id) }
        }
        if let downloadService {
            a.supportsDownload = true
            a.download = { albums in
                for album in albums {
                    guard let full = musicLibrary.albumWithTracks(album.id) else { continue }
                    let artist =
                        musicLibrary.artist(album.artistId)
                        ?? Artist(id: album.artistId, name: "", sortName: "", slug: "")
                    downloadService.download(album: full, artist: artist)
                }
            }
            a.removeDownload = { albums in
                let ids = albums.flatMap {
                    musicLibrary.tracksForAlbum($0.id).filter(\.isDownloaded).map(\.id)
                }
                guard !ids.isEmpty else { return }
                let subject =
                    albums.count == 1
                    ? albums[0].name
                    : String(AttributedString(localized: "^[\(albums.count) album](inflect: true)").characters)
                DownloadRemovalRequest.post(trackIds: Set(ids), subject: subject)
            }
        }
        return a
    }
}
#endif
