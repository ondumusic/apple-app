import Foundation

nonisolated struct Album: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var artistId: UUID
    var name: String
    var sortName: String
    var slug: String
    var releaseYear: Int?
    var tracks: [Track]?
    var isUnknown: Bool
    var artworkUrl: URL?

    init(id: UUID, artistId: UUID, name: String, sortName: String, slug: String,
         releaseYear: Int? = nil, tracks: [Track]? = nil, isUnknown: Bool = false,
         artworkUrl: URL? = nil) {
        self.id = id
        self.artistId = artistId
        self.name = name
        self.sortName = sortName
        self.slug = slug
        self.releaseYear = releaseYear
        self.tracks = tracks
        self.isUnknown = isUnknown
        self.artworkUrl = artworkUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artistId = try container.decode(UUID.self, forKey: .artistId)
        name = try container.decode(String.self, forKey: .name)
        sortName = try container.decodeIfPresent(String.self, forKey: .sortName) ?? name
        slug = try container.decode(String.self, forKey: .slug)
        releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks)
        isUnknown = try container.decode(Bool.self, forKey: .isUnknown)
        artworkUrl = try container.decodeIfPresent(URL.self, forKey: .artworkUrl)
    }
}
