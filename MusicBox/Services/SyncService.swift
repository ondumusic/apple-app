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
    var number: Int?
    var duration: Double
    var mimetype: String
    var streamUrl: String
    var downloadUrl: String
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
        var artistIds: Set<UUID> = []
        var albumIds: Set<UUID> = []
        var trackIds: Set<UUID> = []
        var artistCount: Int { artistIds.count }
        var albumCount: Int { albumIds.count }
        var trackCount: Int { trackIds.count }
    }

    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let settings: SettingsStore?
    @ObservationIgnored private weak var downloadService: DownloadService?
    @ObservationIgnored private var artworkPrefetcher: ImagePrefetcher?

    private var syncCursor: String? {
        get { UserDefaults.standard.string(forKey: "syncCursor") }
        set { UserDefaults.standard.set(newValue, forKey: "syncCursor") }
    }

    init(api: APIService, musicLibrary: MusicLibrary, settings: SettingsStore? = nil, downloadService: DownloadService? = nil) {
        self.api = api
        self.musicLibrary = musicLibrary
        self.settings = settings
        self.downloadService = downloadService
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
        var newTrackIds = Set<UUID>()

        do {
            var pageCount = 0
            while true {
                pageCount += 1
                let response = try await api.fetchSync(cursor: cursor)

                print("SyncService: page \(pageCount) — \(response.artists.count) artists, \(response.albums.count) albums, \(response.tracks.count) tracks, \(response.deletions.count) deletions, complete: \(response.complete)")

                musicLibrary.upsertArtists(response.artists)
                let newAlbumIds = musicLibrary.upsertAlbums(response.albums)
                newTrackIds.formUnion(musicLibrary.upsertTracks(response.tracks))
                musicLibrary.applyDeletions(response.deletions)

                // Only prefetch artwork for newly added albums
                artworkURLs += response.albums
                    .filter { newAlbumIds.contains($0.id) }
                    .compactMap(\.artworkUrl)

                syncProgress?.artistIds.formUnion(response.artists.map(\.id))
                syncProgress?.albumIds.formUnion(response.albums.map(\.id))
                syncProgress?.trackIds.formUnion(response.tracks.map(\.id))

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

        // Single revision bump after all pages — triggers view refreshes once
        musicLibrary.bumpRevision()

        // Prefetch artwork — detached to avoid slowing sync, stored to prevent deallocation
        if !artworkURLs.isEmpty {
            let urls = artworkURLs
            Task.detached(priority: .utility) { @MainActor [weak self] in
                let prefetcher = ImagePrefetcher()
                self?.artworkPrefetcher = prefetcher
                prefetcher.startPrefetching(with: urls)
            }
        }

        // Auto-download new tracks if enabled
        if !newTrackIds.isEmpty,
           settings?.autoDownloadNewTracks == true,
           let downloadService {
            print("SyncService: auto-downloading \(newTrackIds.count) new tracks")
            downloadService.downloadTracks(ids: newTrackIds, library: musicLibrary)
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
