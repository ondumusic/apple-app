import Foundation
import SwiftData

@Model
nonisolated class DownloadedTrack {
    @Attribute(.unique) var id: UUID
    var albumId: UUID
    var artistId: UUID
    var artistName: String
    var name: String
    var number: Int
    var disc: Int
    var duration: Double
    var mimetype: String
    var localFileURL: URL
    var album: DownloadedAlbum?

    init(from track: Track, localFileURL: URL) {
        self.id = track.id
        self.albumId = track.albumId
        self.artistId = track.artistId
        self.artistName = track.artist.name
        self.name = track.name
        self.number = track.number
        self.disc = track.disc
        self.duration = track.duration
        self.mimetype = track.mimetype
        self.localFileURL = localFileURL
    }

    /// Resolves the file URL at runtime from the known path structure,
    /// since the absolute container path can change between builds/launches on iOS.
    var resolvedFileURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ext = localFileURL.pathExtension
        // Use album's artist ID for the path — matches the directory structure
        // created by DownloadService (which uses the album artist, not the track artist)
        let dirArtistId = album?.artistId ?? artistId
        return appSupport
            .appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            .appendingPathComponent(dirArtistId.uuidString, isDirectory: true)
            .appendingPathComponent(albumId.uuidString, isDirectory: true)
            .appendingPathComponent("\(id.uuidString).\(ext)")
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var asTrack: Track {
        Track(
            id: id,
            artistId: artistId,
            albumArtistId: artistId,
            albumId: albumId,
            artist: Artist(id: artistId, name: artistName, sortName: artistName, slug: ""),
            albumArtistSortName: artistName,
            name: name,
            disc: disc,
            number: number,
            duration: duration,
            mimetype: mimetype,
            streamUrl: ""
        )
    }
}
