import Foundation

nonisolated struct Playlist: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var trackCount: Int
    var insertedAt: Date
    var isFolder: Bool
    var parentId: UUID?
    /// Local-only; see `LibraryPlaylist.autoDownload`.
    var autoDownload: Bool

    init(id: UUID, name: String, trackCount: Int, insertedAt: Date,
         isFolder: Bool = false, parentId: UUID? = nil, autoDownload: Bool = false) {
        self.id = id
        self.name = name
        self.trackCount = trackCount
        self.insertedAt = insertedAt
        self.isFolder = isFolder
        self.parentId = parentId
        self.autoDownload = autoDownload
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, trackCount, insertedAt, isFolder, parentId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        insertedAt = try container.decodeIfPresent(Date.self, forKey: .insertedAt) ?? Date()
        isFolder = try container.decodeIfPresent(Bool.self, forKey: .isFolder) ?? false
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
        autoDownload = false
    }
}
