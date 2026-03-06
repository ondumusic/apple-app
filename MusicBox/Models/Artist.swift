import Foundation

nonisolated struct Artist: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var sortName: String
    var slug: String
    var albumCount: Int?

    init(id: UUID, name: String, sortName: String, slug: String, albumCount: Int? = nil) {
        self.id = id
        self.name = name
        self.sortName = sortName
        self.slug = slug
        self.albumCount = albumCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sortName = try container.decodeIfPresent(String.self, forKey: .sortName) ?? name
        slug = try container.decode(String.self, forKey: .slug)
        albumCount = try container.decodeIfPresent(Int.self, forKey: .albumCount)
    }
}
