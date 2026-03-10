import Foundation
import SwiftData

// MARK: - SwiftData Models

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
    var number: Int
    var duration: Double
    var mimetype: String
    var streamUrl: String
    var insertedAt: Date
    var fileSize: Int64
    var fileChecksum: String
    var isDownloaded: Bool = false
    /// Relative path from Application Support directory, e.g. "MusicBox/Downloads/{artistId}/{albumId}/{trackId}.flac"
    var localFilePath: String?

    init(serverId: UUID, artistId: UUID, albumArtistId: UUID, albumId: UUID,
         name: String, disc: Int, number: Int, duration: Double,
         mimetype: String, streamUrl: String, insertedAt: Date,
         fileSize: Int64, fileChecksum: String,
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
        self.insertedAt = insertedAt
        self.fileSize = fileSize
        self.fileChecksum = fileChecksum
        self.isDownloaded = isDownloaded
        self.localFilePath = localFilePath
    }

    /// Resolves the absolute file URL from the stored relative path.
    var resolvedFileURL: URL? {
        guard let localFilePath else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(localFilePath)
    }
}

// MARK: - MusicLibrary

@Observable
final class MusicLibrary {
    @ObservationIgnored let modelContainer: ModelContainer

    /// Incremented on every mutation so views that read it re-evaluate.
    private(set) var revision: UInt = 0

    init() throws {
        let schema = Schema([LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            // Schema changed — delete old store and recreate.
            // Library data is a sync cache and will be re-fetched.
            print("MusicLibrary: schema migration failed, resetting database: \(error)")
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let enumerator = fm.enumerator(at: appSupport, includingPropertiesForKeys: nil)
                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.lastPathComponent.hasSuffix(".store") ||
                       fileURL.lastPathComponent.hasSuffix(".store-wal") ||
                       fileURL.lastPathComponent.hasSuffix(".store-shm") {
                        try? fm.removeItem(at: fileURL)
                    }
                }
            }
            SyncService.clearSyncState()
            modelContainer = try ModelContainer(for: schema)
        }
    }

    var modelContext: ModelContext { modelContainer.mainContext }

    // MARK: - Query: Artists

    func allArtists() -> [Artist] {
        _ = revision
        let libArtists = (try? modelContext.fetch(
            FetchDescriptor<LibraryArtist>(sortBy: [SortDescriptor(\.sortName)])
        )) ?? []
        let libAlbums = (try? modelContext.fetch(FetchDescriptor<LibraryAlbum>())) ?? []
        let albumCounts = Dictionary(grouping: libAlbums.filter { $0.trackCount > 0 }, by: \.artistId)
            .mapValues(\.count)
        return libArtists.compactMap {
            let count = albumCounts[$0.serverId] ?? 0
            guard count > 0 else { return nil }
            return Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName,
                          slug: $0.slug, albumCount: count)
        }
    }

    func artist(_ id: UUID) -> Artist? {
        _ = revision
        guard let la = fetchAllArtists().first(where: { $0.serverId == id }) else { return nil }
        return Artist(id: la.serverId, name: la.name, sortName: la.sortName, slug: la.slug, albumCount: la.albumCount)
    }

    // MARK: - Query: Albums

    func allAlbums() -> [Album] {
        _ = revision
        let libAlbums = fetchAllAlbums()
        let artistMap = buildArtistMap()
        return libAlbums
            .filter { $0.trackCount > 0 }
            .map { toAlbum($0, artistMap: artistMap) }
    }

    func albumsForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        return fetchAllAlbums()
            .filter { $0.artistId == artistId }
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
            .map { toAlbum($0) }
    }

    func album(_ id: UUID) -> Album? {
        _ = revision
        guard let la = fetchAllAlbums().first(where: { $0.serverId == id }) else { return nil }
        return toAlbum(la)
    }

    func track(_ id: UUID) -> Track? {
        _ = revision
        guard let lt = fetchAllTracks().first(where: { $0.serverId == id }) else { return nil }
        let artistMap = buildArtistMap()
        let albumMap = buildAlbumMap()
        return buildTrack(lt, artistMap: artistMap, album: albumMap[lt.albumId])
    }

    func albumWithTracks(_ id: UUID) -> Album? {
        _ = revision
        guard let la = fetchAllAlbums().first(where: { $0.serverId == id }) else { return nil }
        let tracks = tracksForAlbum(id)
        return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
                     slug: la.slug, releaseYear: la.releaseYear, tracks: tracks,
                     isUnknown: la.isUnknown, artworkUrl: la.artworkUrl)
    }

    func albumsWithTracksForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        let libAlbums = fetchAllAlbums()
            .filter { $0.artistId == artistId }
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
        let libTracks = fetchAllTracks().filter { $0.albumArtistId == artistId }

        let artistMap = buildArtistMap()
        let tracksByAlbum = Dictionary(grouping: libTracks, by: \.albumId)

        return libAlbums.map { la in
            let albumTracks = (tracksByAlbum[la.serverId] ?? [])
                .map { buildTrack($0, artistMap: artistMap, album: la) }
                .sorted { ($0.disc, $0.number) < ($1.disc, $1.number) }
            return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
                         slug: la.slug, releaseYear: la.releaseYear, tracks: albumTracks,
                         isUnknown: la.isUnknown, artworkUrl: la.artworkUrl)
        }
    }

    // MARK: - Query: Tracks

    func tracksForAlbum(_ albumId: UUID) -> [Track] {
        _ = revision
        let libTracks = fetchAllTracks().filter { $0.albumId == albumId }
        return buildTracks(from: libTracks)
            .sorted { ($0.disc, $0.number) < ($1.disc, $1.number) }
    }

    func allTracks() -> [Track] {
        _ = revision
        let libTracks = (try? modelContext.fetch(FetchDescriptor<LibraryTrack>())) ?? []
        let artistMap = buildArtistMap()
        let albumMap = buildAlbumMap()
        return libTracks
            .map { buildTrack($0, artistMap: artistMap, album: albumMap[$0.albumId]) }
            .sorted { a, b in
                let aSortName = artistMap[a.albumArtistId]?.sortName ?? ""
                let bSortName = artistMap[b.albumArtistId]?.sortName ?? ""
                if aSortName != bSortName { return aSortName < bSortName }
                let aAlbum = albumMap[a.albumId]?.sortName ?? ""
                let bAlbum = albumMap[b.albumId]?.sortName ?? ""
                if aAlbum != bAlbum { return aAlbum.localizedStandardCompare(bAlbum) == .orderedAscending }
                if a.disc != b.disc { return a.disc < b.disc }
                return a.number < b.number
            }
    }

    // MARK: - Search

    func search(_ query: String) -> (artists: [Artist], albums: [Album], tracks: [Track]) {
        _ = revision
        let query = query.lowercased()
        guard !query.isEmpty else { return ([], [], []) }

        let artistMap = buildArtistMap()

        let artists = fetchAllArtists()
            .filter { $0.name.localizedCaseInsensitiveContains(query) || $0.sortName.localizedCaseInsensitiveContains(query) }
            .filter { $0.albumCount > 0 }
            .sorted { $0.sortName < $1.sortName }
            .map { Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount) }

        let albums = fetchAllAlbums()
            .filter { $0.name.localizedCaseInsensitiveContains(query) || $0.sortName.localizedCaseInsensitiveContains(query) }
            .filter { $0.trackCount > 0 }
            .sorted { a, b in
                let aSortName = artistMap[a.artistId]?.sortName ?? ""
                let bSortName = artistMap[b.artistId]?.sortName ?? ""
                if aSortName != bSortName { return aSortName < bSortName }
                let aYear = a.releaseYear ?? 0
                let bYear = b.releaseYear ?? 0
                if aYear != bYear { return aYear > bYear }
                return a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
            }
            .map { toAlbum($0) }

        let albumMap = buildAlbumMap()
        let tracks = fetchAllTracks()
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .map { buildTrack($0, artistMap: artistMap, album: albumMap[$0.albumId]) }
            .sorted { ($0.artist.sortName, $0.name) < ($1.artist.sortName, $1.name) }

        return (artists, albums, tracks)
    }

    // MARK: - Downloads

    func isDownloaded(trackId: UUID) -> Bool {
        _ = revision
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func downloadedTrackCount(albumId: UUID) -> Int {
        _ = revision
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func isAlbumDownloaded(albumId: UUID) -> Bool {
        _ = revision
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func isAlbumFullyDownloaded(albumId: UUID) -> Bool {
        _ = revision
        let allDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId })
        let downloadedDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        let total = (try? modelContext.fetchCount(allDescriptor)) ?? 0
        let downloaded = (try? modelContext.fetchCount(downloadedDescriptor)) ?? 0
        return total > 0 && total == downloaded
    }

    func isArtistDownloaded(artistId: UUID) -> Bool {
        _ = revision
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func localURL(for trackId: UUID) -> URL? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId && $0.isDownloaded == true })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return nil }
        return track.resolvedFileURL
    }

    /// Returns artists that have at least one downloaded track, sorted by sortName.
    func downloadedArtists() -> [Artist] {
        _ = revision
        let downloaded = fetchAllTracks().filter { $0.isDownloaded }
        let artistIds = Set(downloaded.map(\.albumArtistId))
        let artistMap = buildArtistMap()
        return artistIds.compactMap { id in
            guard let la = artistMap[id] else { return nil }
            let downloadedAlbumIds = Set(downloaded.filter { $0.albumArtistId == id }.map(\.albumId))
            return Artist(id: la.serverId, name: la.name, sortName: la.sortName,
                          slug: la.slug, albumCount: downloadedAlbumIds.count)
        }.sorted { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
    }

    /// Returns all albums that have at least one downloaded track.
    func downloadedAlbums() -> [Album] {
        _ = revision
        let downloaded = fetchAllTracks().filter { $0.isDownloaded }
        let albumIds = Set(downloaded.map(\.albumId))
        let artistMap = buildArtistMap()
        return fetchAllAlbums()
            .filter { albumIds.contains($0.serverId) }
            .map { toAlbum($0, artistMap: artistMap) }
    }

    /// Returns all downloaded tracks, sorted like allTracks().
    func downloadedTracks() -> [Track] {
        _ = revision
        let libTracks = fetchAllTracks().filter { $0.isDownloaded }
        let artistMap = buildArtistMap()
        let albumMap = buildAlbumMap()
        return libTracks
            .map { buildTrack($0, artistMap: artistMap, album: albumMap[$0.albumId]) }
            .sorted { a, b in
                let aSortName = artistMap[a.albumArtistId]?.sortName ?? ""
                let bSortName = artistMap[b.albumArtistId]?.sortName ?? ""
                if aSortName != bSortName { return aSortName < bSortName }
                let aAlbum = albumMap[a.albumId]?.sortName ?? ""
                let bAlbum = albumMap[b.albumId]?.sortName ?? ""
                if aAlbum != bAlbum { return aAlbum.localizedStandardCompare(bAlbum) == .orderedAscending }
                if a.disc != b.disc { return a.disc < b.disc }
                return a.number < b.number
            }
    }

    /// Returns albums for an artist that have at least one downloaded track.
    func downloadedAlbumsForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        let downloaded = fetchAllTracks().filter { $0.isDownloaded && $0.albumArtistId == artistId }
        let albumIds = Set(downloaded.map(\.albumId))
        let artistMap = buildArtistMap()
        return fetchAllAlbums()
            .filter { albumIds.contains($0.serverId) }
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
            .map { toAlbum($0, artistMap: artistMap) }
    }

    func markDownloaded(trackId: UUID, relativePath: String) {
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        track.isDownloaded = true
        track.localFilePath = relativePath
        try? modelContext.save()
        revision += 1
    }

    func markUndownloaded(trackId: UUID) {
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        if let url = track.resolvedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        track.isDownloaded = false
        track.localFilePath = nil
        try? modelContext.save()
        revision += 1
    }

    func markAlbumUndownloaded(albumId: UUID) {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
        }
        try? modelContext.save()
        revision += 1
    }

    func markArtistUndownloaded(artistId: UUID) {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
        }
        try? modelContext.save()
        revision += 1
    }

    func markAllUndownloaded() {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
        }
        // Clean up the entire Downloads directory
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let downloadsDir = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            try? fm.removeItem(at: downloadsDir)
        }
        try? modelContext.save()
        revision += 1
    }

    /// Returns file URLs for all downloaded tracks in an album.
    func downloadedFileURLs(albumId: UUID) -> [URL] {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return [] }
        return tracks.compactMap(\.resolvedFileURL)
    }

    /// Returns file URLs for all downloaded tracks by an artist.
    func downloadedFileURLs(artistId: UUID) -> [URL] {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return [] }
        return tracks.compactMap(\.resolvedFileURL)
    }

    func availableTracks(_ tracks: [Track], isOnline: Bool) -> [Track] {
        if isOnline { return tracks }
        return tracks.filter { isDownloaded(trackId: $0.id) }
    }

    func availableItems(_ items: [QueueItem], isOnline: Bool) -> [QueueItem] {
        if isOnline { return items }
        return items.filter { isDownloaded(trackId: $0.track.id) }
    }

    // MARK: - Mutations (called by SyncService)

    func upsertArtists(_ syncArtists: [SyncArtist]) {
        guard !syncArtists.isEmpty else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<LibraryArtist>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for sa in syncArtists {
            if let la = map[sa.id] {
                la.name = sa.name
                la.sortName = sa.sortName
                la.slug = sa.slug
                la.albumCount = sa.albumCount
                la.insertedAt = sa.insertedAt
            } else {
                modelContext.insert(LibraryArtist(
                    serverId: sa.id, name: sa.name, sortName: sa.sortName,
                    slug: sa.slug, albumCount: sa.albumCount, insertedAt: sa.insertedAt))
            }
        }
        try? modelContext.save()
        revision += 1
    }

    func upsertAlbums(_ syncAlbums: [SyncAlbum]) {
        guard !syncAlbums.isEmpty else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<LibraryAlbum>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for sa in syncAlbums {
            if let la = map[sa.id] {
                la.artistId = sa.artistId
                la.name = sa.name
                la.sortName = sa.sortName
                la.slug = sa.slug
                la.releaseYear = sa.releaseYear
                la.artworkUrl = sa.artworkUrl
                la.isUnknown = sa.isUnknown
                la.trackCount = sa.trackCount
                la.insertedAt = sa.insertedAt
            } else {
                modelContext.insert(LibraryAlbum(
                    serverId: sa.id, artistId: sa.artistId, name: sa.name,
                    sortName: sa.sortName, slug: sa.slug,
                    releaseYear: sa.releaseYear, artworkUrl: sa.artworkUrl,
                    isUnknown: sa.isUnknown, trackCount: sa.trackCount,
                    insertedAt: sa.insertedAt))
            }
        }
        try? modelContext.save()
        revision += 1
    }

    func upsertTracks(_ syncTracks: [SyncTrack]) {
        guard !syncTracks.isEmpty else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<LibraryTrack>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for st in syncTracks {
            if let lt = map[st.id] {
                lt.artistId = st.artistId
                lt.albumArtistId = st.albumArtistId
                lt.albumId = st.albumId
                lt.name = st.name
                lt.disc = st.disc
                lt.number = st.number
                lt.duration = st.duration
                lt.mimetype = st.mimetype
                lt.streamUrl = st.streamUrl
                lt.insertedAt = st.insertedAt
                lt.fileSize = st.file.size
                lt.fileChecksum = st.file.checksum
            } else {
                modelContext.insert(LibraryTrack(
                    serverId: st.id, artistId: st.artistId, albumArtistId: st.albumArtistId,
                    albumId: st.albumId, name: st.name, disc: st.disc, number: st.number,
                    duration: st.duration, mimetype: st.mimetype, streamUrl: st.streamUrl,
                    insertedAt: st.insertedAt, fileSize: st.file.size, fileChecksum: st.file.checksum))
            }
        }
        try? modelContext.save()
        revision += 1
    }

    func applyDeletions(_ deletions: [SyncDeletion]) {
        guard !deletions.isEmpty else { return }
        for deletion in deletions {
            switch deletion.entityType {
            case "artist":
                deleteArtistCascade(deletion.entityId)
            case "album":
                deleteAlbumCascade(deletion.entityId)
            case "track":
                let id = deletion.entityId
                let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == id })
                if let track = try? modelContext.fetch(descriptor).first {
                    if let url = track.resolvedFileURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    modelContext.delete(track)
                }
            default:
                break
            }
        }
        try? modelContext.save()
        revision += 1
    }

    func clearAll() {
        // Remove downloaded files
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let downloadsDir = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            try? fm.removeItem(at: downloadsDir)
        }
        try? modelContext.delete(model: LibraryTrack.self)
        try? modelContext.delete(model: LibraryAlbum.self)
        try? modelContext.delete(model: LibraryArtist.self)
        try? modelContext.save()
        revision += 1
    }

    // MARK: - Private: Fetches

    private func fetchAllArtists() -> [LibraryArtist] {
        (try? modelContext.fetch(FetchDescriptor<LibraryArtist>())) ?? []
    }

    private func fetchAllAlbums() -> [LibraryAlbum] {
        (try? modelContext.fetch(FetchDescriptor<LibraryAlbum>())) ?? []
    }

    private func fetchAllTracks() -> [LibraryTrack] {
        (try? modelContext.fetch(FetchDescriptor<LibraryTrack>())) ?? []
    }

    private func buildArtistMap() -> [UUID: LibraryArtist] {
        Dictionary(uniqueKeysWithValues: fetchAllArtists().map { ($0.serverId, $0) })
    }

    private func buildAlbumMap() -> [UUID: LibraryAlbum] {
        Dictionary(uniqueKeysWithValues: fetchAllAlbums().map { ($0.serverId, $0) })
    }

    // MARK: - Private: Builders

    private func toAlbum(_ la: LibraryAlbum, artistMap: [UUID: LibraryArtist]? = nil) -> Album {
        let artist = artistMap?[la.artistId]
        return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
              slug: la.slug, releaseYear: la.releaseYear, isUnknown: la.isUnknown,
              artworkUrl: la.artworkUrl, insertedAt: la.insertedAt,
              artistName: artist?.name, artistSortName: artist?.sortName)
    }

    private func buildTracks(from libTracks: [LibraryTrack]) -> [Track] {
        let artistMap = buildArtistMap()
        let albumMap = buildAlbumMap()
        return libTracks.map { lt in
            buildTrack(lt, artistMap: artistMap, album: albumMap[lt.albumId])
        }
    }

    private func buildTrack(_ lt: LibraryTrack, artistMap: [UUID: LibraryArtist], album: LibraryAlbum?) -> Track {
        let artist = artistMap[lt.artistId].map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount)
        } ?? Artist(id: lt.artistId, name: "Unknown", sortName: "Unknown", slug: "unknown")

        let trackAlbum = album.map {
            Track.TrackAlbum(id: $0.serverId, name: $0.name, artworkUrl: $0.artworkUrl)
        }

        let albumArtistSortName = artistMap[lt.albumArtistId]?.sortName ?? artist.sortName

        return Track(
            id: lt.serverId, artistId: lt.artistId, albumArtistId: lt.albumArtistId,
            albumId: lt.albumId, artist: artist, albumArtistSortName: albumArtistSortName,
            album: trackAlbum, name: lt.name,
            disc: lt.disc, number: lt.number, duration: lt.duration,
            mimetype: lt.mimetype, streamUrl: lt.streamUrl, fileSize: lt.fileSize
        )
    }

    // MARK: - Private: Cascade Deletes

    private func deleteArtistCascade(_ artistId: UUID) {
        for track in fetchAllTracks().filter({ $0.artistId == artistId }) {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(track)
        }
        for album in fetchAllAlbums().filter({ $0.artistId == artistId }) {
            modelContext.delete(album)
        }
        if let artist = fetchAllArtists().first(where: { $0.serverId == artistId }) {
            modelContext.delete(artist)
        }
    }

    private func deleteAlbumCascade(_ albumId: UUID) {
        for track in fetchAllTracks().filter({ $0.albumId == albumId }) {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(track)
        }
        if let album = fetchAllAlbums().first(where: { $0.serverId == albumId }) {
            modelContext.delete(album)
        }
    }
}
