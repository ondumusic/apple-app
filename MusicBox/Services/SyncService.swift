import Foundation
import Nuke

// MARK: - Sync Response Types

nonisolated struct SyncResponse: Decodable, Sendable {
    var artists: [SyncArtist]
    var albums: [SyncAlbum]
    var tracks: [SyncTrack]
    var playlists: [SyncPlaylist]
    var playlistItems: [SyncPlaylistItem]
    var deletions: [SyncDeletion]
    var cursor: String
    var complete: Bool

    nonisolated enum CodingKeys: String, CodingKey {
        case artists, albums, tracks, playlists, playlistItems, deletions, cursor, complete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artists = try container.decode([SyncArtist].self, forKey: .artists)
        albums = try container.decode([SyncAlbum].self, forKey: .albums)
        tracks = try container.decode([SyncTrack].self, forKey: .tracks)
        playlists = try container.decodeIfPresent([SyncPlaylist].self, forKey: .playlists) ?? []
        playlistItems = try container.decodeIfPresent([SyncPlaylistItem].self, forKey: .playlistItems) ?? []
        deletions = try container.decode([SyncDeletion].self, forKey: .deletions)
        cursor = try container.decode(String.self, forKey: .cursor)
        complete = try container.decode(Bool.self, forKey: .complete)
    }
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

/// The server sends loudness as `{ lufs, peak }` on both tracks and albums. Only `lufs`
/// is read: `peak` guards against clipping when boosting, and we can't boost.
nonisolated enum LoudnessKeys: String, CodingKey {
    case lufs
}

nonisolated struct SyncAlbum: Sendable {
    var id: UUID
    var artistId: UUID
    var name: String
    var sortName: String
    var slug: String
    var releaseYear: Int?
    var artworkUrl: URL?
    var artwork: [ArtworkVariant] = []
    var isUnknown: Bool
    var trackCount: Int
    var insertedAt: Date
    var lufs: Double?
}

extension SyncAlbum: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, artistId, name, sortName, slug, releaseYear, artworkUrl, artwork,
             isUnknown, trackCount, insertedAt, loudness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artistId = try container.decode(UUID.self, forKey: .artistId)
        name = try container.decode(String.self, forKey: .name)
        sortName = try container.decodeIfPresent(String.self, forKey: .sortName) ?? name
        slug = try container.decode(String.self, forKey: .slug)
        releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear)
        artwork = try container.decodeIfPresent([ArtworkVariant].self, forKey: .artwork) ?? []
        // `artworkUrl` is deprecated and documented as the largest variant. Derive it
        // from the variants when they're there, so its eventual removal is a no-op.
        let deprecatedArtworkUrl = try container.decodeIfPresent(URL.self, forKey: .artworkUrl)
        artworkUrl = artwork.largest?.url ?? deprecatedArtworkUrl
        isUnknown = try container.decode(Bool.self, forKey: .isUnknown)
        trackCount = try container.decode(Int.self, forKey: .trackCount)
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
        let loudness = try? container.nestedContainer(keyedBy: LoudnessKeys.self, forKey: .loudness)
        lufs = try loudness?.decodeIfPresent(Double.self, forKey: .lufs)
    }
}

nonisolated struct SyncTrack: Sendable {
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
    /// Integrated loudness in LUFS. Nil until the server has measured the file.
    var lufs: Double?
    var playCount: Int = 0
    /// Nil until it has been played once.
    var lastPlayedAt: Date?
}

extension SyncTrack: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, artistId, albumArtistId, albumId, name, disc, number,
             duration, mimetype, streamUrl, downloadUrl, insertedAt, loudness,
             playCount, lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        artistId = try container.decode(UUID.self, forKey: .artistId)
        albumArtistId = try container.decode(UUID.self, forKey: .albumArtistId)
        albumId = try container.decode(UUID.self, forKey: .albumId)
        name = try container.decode(String.self, forKey: .name)
        disc = try container.decodeIfPresent(Int.self, forKey: .disc) ?? 1
        number = try container.decodeIfPresent(Int.self, forKey: .number)
        duration = try container.decode(Double.self, forKey: .duration)
        mimetype = try container.decode(String.self, forKey: .mimetype)
        streamUrl = try container.decode(String.self, forKey: .streamUrl)
        downloadUrl = try container.decode(String.self, forKey: .downloadUrl)
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
        let loudness = try? container.nestedContainer(keyedBy: LoudnessKeys.self, forKey: .loudness)
        lufs = try loudness?.decodeIfPresent(Double.self, forKey: .lufs)
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    }
}

nonisolated struct SyncPlaylist: Sendable {
    var id: UUID
    var name: String
    var trackCount: Int
    var insertedAt: Date
    var isFolder: Bool
    var parentId: UUID?
}

extension SyncPlaylist: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, name, trackCount, insertedAt, isFolder, parentId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
        isFolder = try container.decodeIfPresent(Bool.self, forKey: .isFolder) ?? false
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
    }
}

nonisolated struct SyncPlaylistItem: Sendable {
    var id: UUID
    var playlistId: UUID
    var trackId: UUID
    var position: String
    var insertedAt: Date
}

extension SyncPlaylistItem: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, playlistId, trackId, position, insertedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        playlistId = try container.decode(UUID.self, forKey: .playlistId)
        trackId = try container.decode(UUID.self, forKey: .trackId)
        position = try container.decode(String.self, forKey: .position)
        insertedAt = try container.decode(Date.self, forKey: .insertedAt)
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
    @ObservationIgnored private var downloadService: DownloadService?
    @ObservationIgnored private weak var outbox: OutboxService?
    @ObservationIgnored private var artworkPrefetcher: ImagePrefetcher?
    @ObservationIgnored private var isSessionExpired = false

    private var syncCursor: String? {
        get { UserDefaults.standard.string(forKey: "syncCursor") }
        set { UserDefaults.standard.set(newValue, forKey: "syncCursor") }
    }

    init(api: APIService, musicLibrary: MusicLibrary, settings: SettingsStore? = nil, downloadService: DownloadService? = nil, outbox: OutboxService? = nil) {
        self.api = api
        self.musicLibrary = musicLibrary
        self.settings = settings
        self.downloadService = downloadService
        self.outbox = outbox
        self.hasCompletedInitialSync = UserDefaults.standard.string(forKey: "syncCursor") != nil
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date

        NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: .main) { [weak self] _ in
            self?.isSessionExpired = true
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        if isSessionExpired {
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
            return
        }

        // Drain any queued playlist mutations first so the server's view reflects them before
        // we pull its state back down.
        await outbox?.flush()

        isSyncing = true
        syncProgress = SyncProgress()
        syncError = nil
        defer {
            isSyncing = false
            syncProgress = nil
        }

        let isInitialSync = syncCursor == nil
        if isInitialSync {
            // Downloads survive: the files are still valid, and reconcileDownloadedFiles()
            // re-marks them from the manifest once the tracks come back.
            musicLibrary.clearAll()
        }

        var cursor = syncCursor

        var artworkURLs: [URL] = []
        var newTrackIds = Set<UUID>()
        var changedAnything = false

        do {
            var pageCount = 0
            while true {
                pageCount += 1
                let response = try await api.fetchSync(cursor: cursor)

                #if DEBUG
                print("SyncService: page \(pageCount) — \(response.artists.count) artists, \(response.albums.count) albums, \(response.tracks.count) tracks, \(response.deletions.count) deletions, complete: \(response.complete)")
                #endif

                if !response.artists.isEmpty || !response.albums.isEmpty
                    || !response.tracks.isEmpty || !response.playlists.isEmpty
                    || !response.playlistItems.isEmpty || !response.deletions.isEmpty {
                    changedAnything = true
                }
                musicLibrary.upsertArtists(response.artists)
                let newAlbumIds = musicLibrary.upsertAlbums(response.albums)
                newTrackIds.formUnion(musicLibrary.upsertTracks(response.tracks))
                musicLibrary.upsertPlaylists(response.playlists)
                musicLibrary.upsertPlaylistItems(response.playlistItems)
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
                    #if DEBUG
                    print("SyncService: sync complete — \(syncProgress?.artistCount ?? 0) artists, \(syncProgress?.albumCount ?? 0) albums, \(syncProgress?.trackCount ?? 0) tracks total")
                    #endif
                    // Rebuild download state from on-disk manifest if a prior store reset left one behind.
                    musicLibrary.reconcileDownloadedFiles()
                    break
                }
            }
        } catch APIError.unauthorized {
            syncError = "Session expired"
            #if DEBUG
            print("SyncService: sync failed with auth error")
            #endif
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
        } catch {
            syncError = error.localizedDescription
            #if DEBUG
            print("SyncService: sync failed: \(error)")
            #endif
        }

        // Single revision bump after all pages — triggers view refreshes once. Skipped
        // when the delta was empty, which is what most foreground syncs return: bumping
        // regardless threw away the tracks cache every five minutes for nothing, and the
        // next Songs open paid a full rebuild for it.
        if changedAnything {
            musicLibrary.bumpRevision()
            // Rebuild off the main actor so the cost doesn't land on whoever opens Songs
            // next — see MusicLibrary.prepareAllTracks().
            Task { [musicLibrary] in await musicLibrary.prepareAllTracks() }
        }

        // Prefetch artwork — detached to avoid slowing sync, stored to prevent deallocation
        if !artworkURLs.isEmpty {
            let urls = artworkURLs
            Task.detached(priority: .utility) { @MainActor [weak self] in
                let prefetcher = ImagePrefetcher()
                self?.artworkPrefetcher = prefetcher
                prefetcher.startPrefetching(with: urls)
            }
        }

        if let downloadService {
            // Global "auto-download new tracks" setting — only applies if enabled, and
            // never on an initial sync. A rebuild or a fresh login reinserts the whole
            // library, and "new tracks" means ones added on the server since last time,
            // not every track there is.
            let globalAutoIds: Set<UUID> = (settings?.autoDownloadNewTracks == true && !isInitialSync)
                ? newTrackIds : []
            if !globalAutoIds.isEmpty {
                #if DEBUG
                print("SyncService: auto-downloading \(globalAutoIds.count) new tracks")
                #endif
                downloadService.downloadTracks(ids: globalAutoIds, library: musicLibrary)
            }

            // Per-playlist: any track in an auto-downloaded playlist that isn't downloaded yet.
            // Covers new items synced from another device plus any backfill. Subtract only the
            // ids we already handled above — if the global setting was off, a brand-new track
            // that also lives in an auto-downloaded playlist must still be queued here.
            let playlistAutoIds = musicLibrary.tracksNeedingAutoDownload().subtracting(globalAutoIds)
            if !playlistAutoIds.isEmpty {
                #if DEBUG
                print("SyncService: auto-downloading \(playlistAutoIds.count) track(s) for downloaded playlists")
                #endif
                downloadService.downloadTracks(ids: playlistAutoIds, library: musicLibrary)
            }
        }
    }

    func syncIfNeeded() async {
        guard !isSyncing, !isSessionExpired else { return }
        if let lastSync = lastSyncDate, Date().timeIntervalSince(lastSync) < 300 {
            return
        }
        await sync()
    }

    /// Throws away the cursor and re-pages the whole library from scratch.
    ///
    /// A delta sync only sends what changed since the cursor, so a field added to the
    /// client after the server already sent those rows — loudness was the first — is
    /// invisible forever on an install whose cursor has outrun it. This is the way back.
    /// Downloaded files are kept.
    func rebuildLibrary() async {
        MusicLibrary.writeReconciliationManifest()
        Self.clearSyncState()
        syncCursor = nil
        hasCompletedInitialSync = false
        await sync()
    }

    static func clearSyncState() {
        UserDefaults.standard.removeObject(forKey: "syncCursor")
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
    }
}
