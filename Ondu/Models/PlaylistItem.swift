import Foundation

nonisolated struct PlaylistItem: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var playlistId: UUID
    var trackId: UUID
    var position: String
    var insertedAt: Date

    init(id: UUID, playlistId: UUID, trackId: UUID, position: String, insertedAt: Date) {
        self.id = id
        self.playlistId = playlistId
        self.trackId = trackId
        self.position = position
        self.insertedAt = insertedAt
    }
}
