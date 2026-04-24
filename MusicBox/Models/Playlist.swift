import Foundation

nonisolated struct Playlist: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var trackCount: Int
    var insertedAt: Date
    /// Local-only; see `LibraryPlaylist.autoDownload`.
    var autoDownload: Bool

    init(id: UUID, name: String, trackCount: Int, insertedAt: Date, autoDownload: Bool = false) {
        self.id = id
        self.name = name
        self.trackCount = trackCount
        self.insertedAt = insertedAt
        self.autoDownload = autoDownload
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, trackCount, insertedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        insertedAt = try container.decodeIfPresent(Date.self, forKey: .insertedAt) ?? Date()
        autoDownload = false
    }
}
