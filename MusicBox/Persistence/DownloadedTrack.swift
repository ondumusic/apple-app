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

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
