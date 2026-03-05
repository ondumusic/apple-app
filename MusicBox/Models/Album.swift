import Foundation

nonisolated struct Album: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var artistId: UUID
    var name: String
    var slug: String
    var releaseYear: Int?
    var tracks: [Track]?
    var isUnknown: Bool
    var artworkUrl: URL?
}
