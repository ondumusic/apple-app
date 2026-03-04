import Foundation

nonisolated struct Track: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var artistId: UUID
    var albumArtistId: UUID
    var albumId: UUID
    var artist: Artist
    var name: String
    var disc: Int
    var number: Int
    var duration: Double
    var mimetype: String
    var streamUrl: String

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
