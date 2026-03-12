import Foundation

nonisolated struct Track: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var artistId: UUID
    var albumArtistId: UUID
    var albumId: UUID
    var artist: Artist
    var albumArtistSortName: String
    var album: TrackAlbum?
    var name: String
    var disc: Int
    var number: Int
    var duration: Double
    var mimetype: String
    var streamUrl: String
    var downloadUrl: String
    var fileSize: Int64
    var isDownloaded: Bool

    nonisolated struct TrackAlbum: Codable, Sendable, Hashable {
        var id: UUID
        var name: String
        var artworkUrl: URL?
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    init(id: UUID, artistId: UUID, albumArtistId: UUID, albumId: UUID,
         artist: Artist, albumArtistSortName: String, album: TrackAlbum? = nil,
         name: String, disc: Int, number: Int, duration: Double,
         mimetype: String, streamUrl: String, downloadUrl: String = "", fileSize: Int64 = 0,
         isDownloaded: Bool = false) {
        self.id = id
        self.artistId = artistId
        self.albumArtistId = albumArtistId
        self.albumId = albumId
        self.artist = artist
        self.albumArtistSortName = albumArtistSortName
        self.album = album
        self.name = name
        self.disc = disc
        self.number = number
        self.duration = duration
        self.mimetype = mimetype
        self.streamUrl = streamUrl
        self.downloadUrl = downloadUrl
        self.fileSize = fileSize
        self.isDownloaded = isDownloaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artistId = try container.decode(UUID.self, forKey: .artistId)
        albumArtistId = try container.decode(UUID.self, forKey: .albumArtistId)
        albumId = try container.decode(UUID.self, forKey: .albumId)
        artist = try container.decode(Artist.self, forKey: .artist)
        albumArtistSortName = try container.decodeIfPresent(String.self, forKey: .albumArtistSortName) ?? artist.sortName
        album = try container.decodeIfPresent(TrackAlbum.self, forKey: .album)
        name = try container.decode(String.self, forKey: .name)
        disc = try container.decode(Int.self, forKey: .disc)
        number = try container.decode(Int.self, forKey: .number)
        duration = try container.decode(Double.self, forKey: .duration)
        mimetype = try container.decode(String.self, forKey: .mimetype)
        streamUrl = try container.decode(String.self, forKey: .streamUrl)
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl) ?? streamUrl
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        isDownloaded = false
    }
}
