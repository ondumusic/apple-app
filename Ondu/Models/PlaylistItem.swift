import Foundation

nonisolated struct PlaylistItem: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var playlistId: UUID
    var trackId: UUID
    var position: String
    var insertedAt: Date
}
