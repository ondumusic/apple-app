import Foundation

nonisolated struct Track: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var artistId: UUID
    var albumArtistId: UUID
    var albumId: UUID
    var artist: Artist
    var albumArtistName: String
    var albumArtistSortName: String
    var album: TrackAlbum?
    var name: String
    var disc: Int
    var number: Int?
    var duration: Double
    var mimetype: String
    var streamUrl: String
    var downloadUrl: String
    var isDownloaded: Bool
    /// Integrated loudness in LUFS. Nil until the server has measured the file.
    var lufs: Double?
    var playCount: Int
    /// Nil until it has been played once.
    var lastPlayedAt: Date?

    nonisolated struct TrackAlbum: Codable, Sendable, Hashable {
        var id: UUID
        var name: String
        var artworkUrl: URL?
        var releaseYear: Int?
    }

    var formattedDuration: String {
        DurationFormat.string(duration)
    }

    init(
        id: UUID, artistId: UUID, albumArtistId: UUID, albumId: UUID,
        artist: Artist, albumArtistName: String? = nil, albumArtistSortName: String,
        album: TrackAlbum? = nil,
        name: String, disc: Int, number: Int?, duration: Double,
        mimetype: String, streamUrl: String, downloadUrl: String = "",
        isDownloaded: Bool = false, lufs: Double? = nil,
        playCount: Int = 0, lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.artistId = artistId
        self.albumArtistId = albumArtistId
        self.albumId = albumId
        self.artist = artist
        self.albumArtistName = albumArtistName ?? artist.name
        self.albumArtistSortName = albumArtistSortName
        self.album = album
        self.name = name
        self.disc = disc
        self.number = number
        self.duration = duration
        self.mimetype = mimetype
        self.streamUrl = streamUrl
        self.downloadUrl = downloadUrl
        self.isDownloaded = isDownloaded
        self.lufs = lufs
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artistId = try container.decode(UUID.self, forKey: .artistId)
        albumArtistId = try container.decode(UUID.self, forKey: .albumArtistId)
        albumId = try container.decode(UUID.self, forKey: .albumId)
        artist = try container.decode(Artist.self, forKey: .artist)
        albumArtistName = try container.decodeIfPresent(String.self, forKey: .albumArtistName) ?? artist.name
        albumArtistSortName =
            try container.decodeIfPresent(String.self, forKey: .albumArtistSortName) ?? artist.sortName
        album = try container.decodeIfPresent(TrackAlbum.self, forKey: .album)
        name = try container.decode(String.self, forKey: .name)
        disc = try container.decodeIfPresent(Int.self, forKey: .disc) ?? 1
        number = try container.decodeIfPresent(Int.self, forKey: .number)
        duration = try container.decode(Double.self, forKey: .duration)
        mimetype = try container.decode(String.self, forKey: .mimetype)
        streamUrl = try container.decode(String.self, forKey: .streamUrl)
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl) ?? streamUrl
        isDownloaded = false
        lufs = try container.decodeIfPresent(Double.self, forKey: .lufs)
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    }
}
