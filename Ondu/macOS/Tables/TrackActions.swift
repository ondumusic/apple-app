#if os(macOS)
import Foundation

/// Actions a tracks table can invoke. Each detail view populates these from its
/// SwiftUI @Environment values and passes the struct down so the AppKit table can
/// trigger the right work without re-grabbing environment refs from a non-SwiftUI
/// context. Multi-track variants take an array; single-track variants are for menu
/// items that only make sense for one row (e.g. "Go to Artist").
@MainActor
struct TrackActions {
    var play: ([Track]) -> Void = { _ in }
    var playNext: ([Track]) -> Void = { _ in }
    var addToEnd: ([Track]) -> Void = { _ in }
    var addToPlaylist: ([UUID]) -> Void = { ids in
        NotificationCenter.default.post(name: .requestAddToPlaylist, object: ids)
    }
    var goToAlbum: (Track) -> Void = { _ in }
    var goToArtist: (Track) -> Void = { _ in }
    /// Set on PlaylistDetailMac so the context menu can offer "Remove from Playlist".
    /// Receives row indices (not track ids) because playlists can contain duplicates and
    /// the caller needs the exact item position.
    var removeFromPlaylistRows: ((IndexSet) -> Void)?
    /// Download / remove-download for the given tracks. Wired by `standard` when a
    /// DownloadService is supplied; otherwise no-ops and the context menu skips them.
    var download: ([Track]) -> Void = { _ in }
    var removeDownload: ([Track]) -> Void = { _ in }
    /// True if download wiring is available — context menu uses this to decide whether
    /// to offer the Download / Remove Download item.
    var supportsDownload: Bool = false

    /// Standard wiring used by every detail view that hosts a TracksTable. Detail views
    /// can override individual closures (e.g. AlbumDetailMac passes the album artwork
    /// URL through to the player) — but most just want this default.
    static func standard(
        player: PlayerService,
        musicLibrary: MusicLibrary,
        network: NetworkMonitor,
        downloadService: DownloadService? = nil,
        artworkURL: URL? = nil
    ) -> TrackActions {
        var a = TrackActions()
        a.play = { tracks in
            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playNow(tracks: available, artworkURL: artworkURL) }
        }
        a.playNext = { tracks in
            player.playNext(tracks: tracks, artworkURL: artworkURL)
        }
        a.addToEnd = { tracks in
            player.addToEnd(tracks: tracks, artworkURL: artworkURL)
        }
        a.goToAlbum = { track in
            if let album = musicLibrary.albumWithTracks(track.albumId) {
                MainWindowNavigation.request(.navigateToAlbum, object: album)
            }
        }
        a.goToArtist = { track in
            // Navigate to the album artist — track-level artists (e.g. featurings)
            // aren't in the Artists list and would fail to resolve.
            if let artist = musicLibrary.artist(track.albumArtistId) {
                MainWindowNavigation.request(.navigateToArtist, object: artist)
            }
        }
        if let downloadService {
            a.supportsDownload = true
            a.download = { tracks in
                for track in tracks where !musicLibrary.isDownloaded(trackId: track.id) {
                    guard let album = musicLibrary.album(track.albumId),
                          let artist = musicLibrary.artist(album.artistId) ?? Optional(track.artist)
                    else { continue }
                    downloadService.download(track: track, album: album, artist: artist)
                }
            }
            a.removeDownload = { tracks in
                let ids = Set(tracks.filter(\.isDownloaded).map(\.id))
                DownloadRemovalRequest.post(
                    trackIds: ids,
                    subject: tracks.count == 1
                        ? tracks[0].name
                        : DownloadRemovalRequest.songSubject(count: ids.count)
                )
            }
        }
        return a
    }
}
#endif
