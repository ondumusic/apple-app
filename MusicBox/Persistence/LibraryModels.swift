import Foundation
import SwiftData

@Model
nonisolated class LibraryArtist {
    @Attribute(.unique) var serverId: UUID
    var name: String
    var sortName: String
    var slug: String
    var albumCount: Int
    var insertedAt: Date

    init(serverId: UUID, name: String, sortName: String, slug: String, albumCount: Int, insertedAt: Date) {
        self.serverId = serverId
        self.name = name
        self.sortName = sortName
        self.slug = slug
        self.albumCount = albumCount
        self.insertedAt = insertedAt
    }
}

@Model
nonisolated class LibraryAlbum {
    @Attribute(.unique) var serverId: UUID
    var artistId: UUID
    var name: String
    var sortName: String
    var slug: String
    var releaseYear: Int?
    var artworkUrl: URL?
    var isUnknown: Bool
    var trackCount: Int
    var insertedAt: Date

    init(serverId: UUID, artistId: UUID, name: String, sortName: String, slug: String,
         releaseYear: Int?, artworkUrl: URL?, isUnknown: Bool, trackCount: Int, insertedAt: Date) {
        self.serverId = serverId
        self.artistId = artistId
        self.name = name
        self.sortName = sortName
        self.slug = slug
        self.releaseYear = releaseYear
        self.artworkUrl = artworkUrl
        self.isUnknown = isUnknown
        self.trackCount = trackCount
        self.insertedAt = insertedAt
    }
}

@Model
nonisolated class LibraryTrack {
    @Attribute(.unique) var serverId: UUID
    var artistId: UUID
    var albumArtistId: UUID
    var albumId: UUID
    var name: String
    var disc: Int
    var number: Int?
    var duration: Double
    var mimetype: String
    var streamUrl: String
    var downloadUrl: String = ""
    var insertedAt: Date
    var isDownloaded: Bool = false
    /// Actual size of the downloaded file on disk
    var downloadedFileSize: Int64 = 0
    /// Relative path from Application Support directory, e.g. "MusicBox/Downloads/{artistId}/{albumId}/{trackId}.flac"
    var localFilePath: String?

    init(serverId: UUID, artistId: UUID, albumArtistId: UUID, albumId: UUID,
         name: String, disc: Int, number: Int?, duration: Double,
         mimetype: String, streamUrl: String, downloadUrl: String = "", insertedAt: Date,
         isDownloaded: Bool = false, localFilePath: String? = nil) {
        self.serverId = serverId
        self.artistId = artistId
        self.albumArtistId = albumArtistId
        self.albumId = albumId
        self.name = name
        self.disc = disc
        self.number = number
        self.duration = duration
        self.mimetype = mimetype
        self.streamUrl = streamUrl
        self.downloadUrl = downloadUrl
        self.insertedAt = insertedAt
        self.isDownloaded = isDownloaded
        self.localFilePath = localFilePath
    }

    /// Resolves the absolute file URL from the stored relative path.
    var resolvedFileURL: URL? {
        guard let localFilePath else { return nil }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent(localFilePath)
    }
}

@Model
nonisolated class LibraryPlaylist {
    @Attribute(.unique) var serverId: UUID
    var name: String
    var trackCount: Int
    var insertedAt: Date
    var isFolder: Bool = false
    var parentId: UUID?
    /// Local-only flag set when the user taps Download on the playlist; cleared on Remove
    /// Download. Drives auto-downloading of subsequent additions (local or synced). Not sent
    /// to or from the server.
    var autoDownload: Bool = false

    init(serverId: UUID, name: String, trackCount: Int, insertedAt: Date,
         isFolder: Bool = false, parentId: UUID? = nil, autoDownload: Bool = false) {
        self.serverId = serverId
        self.name = name
        self.trackCount = trackCount
        self.insertedAt = insertedAt
        self.isFolder = isFolder
        self.parentId = parentId
        self.autoDownload = autoDownload
    }
}

@Model
nonisolated class LibraryPlaylistItem {
    @Attribute(.unique) var serverId: UUID
    var playlistId: UUID
    var trackId: UUID
    var position: String
    var insertedAt: Date

    init(serverId: UUID, playlistId: UUID, trackId: UUID, position: String, insertedAt: Date) {
        self.serverId = serverId
        self.playlistId = playlistId
        self.trackId = trackId
        self.position = position
        self.insertedAt = insertedAt
    }
}

/// Durable queue of playlist mutations pending replay to the server.
/// Processed in `createdAt` order; temp UUIDs assigned locally are resolved to server UUIDs
/// on successful replay, and subsequent payloads referencing those temp IDs are rewritten.
@Model
nonisolated class PendingMutation {
    @Attribute(.unique) var localId: UUID
    /// One of `OutboxKind.rawValue`
    var kind: String
    /// JSON-encoded payload specific to `kind`
    var payload: Data
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?
    var lastAttemptAt: Date?

    init(localId: UUID = UUID(), kind: String, payload: Data, createdAt: Date = Date()) {
        self.localId = localId
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.attemptCount = 0
    }
}
