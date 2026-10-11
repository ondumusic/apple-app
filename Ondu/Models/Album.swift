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
    /// The largest variant. Retained because most of the app still asks for one URL;
    /// prefer `artwork.covering(pixelWidth:)` where the display size is known.
    var artworkUrl: URL?
    var artwork: [ArtworkVariant]
    var insertedAt: Date?
    var artistName: String?
    var artistSortName: String?

    init(
        id: UUID, artistId: UUID, name: String, sortName: String, slug: String,
        releaseYear: Int? = nil, tracks: [Track]? = nil, isUnknown: Bool = false,
        artworkUrl: URL? = nil, artwork: [ArtworkVariant] = [], insertedAt: Date? = nil,
        artistName: String? = nil, artistSortName: String? = nil
    ) {
        self.id = id
        self.artistId = artistId
        self.name = name
        self.sortName = sortName
        self.slug = slug
        self.releaseYear = releaseYear
        self.tracks = tracks
        self.isUnknown = isUnknown
        self.artworkUrl = artworkUrl ?? artwork.largest?.url
        self.artwork = artwork
        self.insertedAt = insertedAt
        self.artistName = artistName
        self.artistSortName = artistSortName
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
        artwork = try container.decodeIfPresent([ArtworkVariant].self, forKey: .artwork) ?? []
        // Prefer the variants: `artworkUrl` is deprecated server-side and documented as
        // the largest of them, so deriving it here makes its removal a non-event.
        let deprecatedArtworkUrl = try container.decodeIfPresent(URL.self, forKey: .artworkUrl)
        artworkUrl = artwork.largest?.url ?? deprecatedArtworkUrl
        insertedAt = try container.decodeIfPresent(Date.self, forKey: .insertedAt)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        artistSortName = try container.decodeIfPresent(String.self, forKey: .artistSortName)
    }
}
