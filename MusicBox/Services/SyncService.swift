import Foundation
import Nuke

// MARK: - Sync Response Types

nonisolated struct SyncResponse: Decodable, Sendable {
    var artists: [SyncArtist]
    var albums: [SyncAlbum]
    var tracks: [SyncTrack]
    var deletions: [SyncDeletion]
    var cursor: String
    var complete: Bool
}

nonisolated struct SyncArtist: Sendable {
    var id: UUID
    var name: String
    var sortName: String
    var slug: String
    var albumCount: Int
    var insertedAt: Date
}

extension SyncArtist: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, sortName, slug, albumCount, insertedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sortName = try container.decodeIfPresent(String.self, forKey: .sortName) ?? name
        slug = try container.decode(String.self, forKey: .slug)
        albumCount = try container.decode(Int.self, forKey: .albumCount)
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
    }
}

nonisolated struct SyncAlbum: Sendable {
    var id: UUID
    var artistId: UUID
    var name: String
    var sortName: String
    var slug: String
    var releaseYear: Int?
    var artworkUrl: URL?
    var isUnknown: Bool
    var trackCount: Int
    var insertedAt: Date
}

extension SyncAlbum: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, artistId, name, sortName, slug, releaseYear, artworkUrl, isUnknown, trackCount, insertedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artistId = try container.decode(UUID.self, forKey: .artistId)
        name = try container.decode(String.self, forKey: .name)
        sortName = try container.decodeIfPresent(String.self, forKey: .sortName) ?? name
        slug = try container.decode(String.self, forKey: .slug)
        releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear)
        artworkUrl = try container.decodeIfPresent(URL.self, forKey: .artworkUrl)
        isUnknown = try container.decode(Bool.self, forKey: .isUnknown)
        trackCount = try container.decode(Int.self, forKey: .trackCount)
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
    }
}

nonisolated struct SyncTrack: Decodable, Sendable {
    var id: UUID
    var artistId: UUID
    var albumArtistId: UUID
    var albumId: UUID
    var name: String
    var disc: Int
    var number: Int
    var duration: Double
    var mimetype: String
    var streamUrl: String
    var insertedAt: Date
    var file: SyncFile

    nonisolated struct SyncFile: Decodable, Sendable {
        var size: Int64
        var checksum: String
    }
}

nonisolated struct SyncDeletion: Decodable, Sendable {
    var entityType: String
    var entityId: UUID
}

// MARK: - SyncService

@Observable
final class SyncService {
    var isSyncing = false
    var hasCompletedInitialSync: Bool
    var lastSyncDate: Date?
    var syncProgress: SyncProgress?
    var syncError: String?

    nonisolated struct SyncProgress: Sendable {
        var artistCount: Int = 0
        var albumCount: Int = 0
        var trackCount: Int = 0
    }

    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let musicLibrary: MusicLibrary

    private var syncCursor: String? {
        get { UserDefaults.standard.string(forKey: "syncCursor") }
        set { UserDefaults.standard.set(newValue, forKey: "syncCursor") }
    }

    init(api: APIService, musicLibrary: MusicLibrary) {
        self.api = api
        self.musicLibrary = musicLibrary
        self.hasCompletedInitialSync = UserDefaults.standard.string(forKey: "syncCursor") != nil
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncProgress = SyncProgress()
        syncError = nil
        defer {
            isSyncing = false
            syncProgress = nil
        }

        let isInitialSync = syncCursor == nil
        if isInitialSync {
            musicLibrary.clearAll()
        }

        var cursor = syncCursor

        var artworkURLs: [URL] = []

        do {
            var pageCount = 0
            while true {
                pageCount += 1
                let response = try await api.fetchSync(cursor: cursor)

                print("SyncService: page \(pageCount) — \(response.artists.count) artists, \(response.albums.count) albums, \(response.tracks.count) tracks, \(response.deletions.count) deletions, complete: \(response.complete)")

                musicLibrary.upsertArtists(response.artists)
                musicLibrary.upsertAlbums(response.albums)
                musicLibrary.upsertTracks(response.tracks)
                musicLibrary.applyDeletions(response.deletions)

                artworkURLs += response.albums.compactMap(\.artworkUrl)

                syncProgress?.artistCount += response.artists.count
                syncProgress?.albumCount += response.albums.count
                syncProgress?.trackCount += response.tracks.count

                cursor = response.cursor

                if response.complete {
                    syncCursor = cursor
                    lastSyncDate = Date()
                    UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
                    hasCompletedInitialSync = true
                    print("SyncService: sync complete — \(syncProgress?.artistCount ?? 0) artists, \(syncProgress?.albumCount ?? 0) albums, \(syncProgress?.trackCount ?? 0) tracks total")
                    break
                }
            }
        } catch {
            syncError = error.localizedDescription
            print("SyncService: sync failed: \(error)")
        }

        if !artworkURLs.isEmpty {
            let prefetcher = ImagePrefetcher()
            prefetcher.startPrefetching(with: artworkURLs)
        }
    }

    func syncIfNeeded() async {
        guard !isSyncing else { return }
        if let lastSync = lastSyncDate, Date().timeIntervalSince(lastSync) < 300 {
            return
        }
        await sync()
    }

    static func clearSyncState() {
        UserDefaults.standard.removeObject(forKey: "syncCursor")
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
    }
}
