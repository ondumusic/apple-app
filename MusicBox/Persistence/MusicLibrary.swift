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
    var downloadUrl: String = ""
    var insertedAt: Date
    var fileSize: Int64
    var fileChecksum: String
    var isDownloaded: Bool = false
    /// Actual size of the downloaded file (may differ from fileSize if transcoded)
    var downloadedFileSize: Int64 = 0
    /// Relative path from Application Support directory, e.g. "MusicBox/Downloads/{artistId}/{albumId}/{trackId}.flac"
    var localFilePath: String?

    init(serverId: UUID, artistId: UUID, albumArtistId: UUID, albumId: UUID,
         name: String, disc: Int, number: Int, duration: Double,
         mimetype: String, streamUrl: String, downloadUrl: String = "", insertedAt: Date,
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
        self.downloadUrl = downloadUrl
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

    /// Incremented on content mutations (sync, clear) so views that read it re-evaluate.
    private(set) var revision: UInt = 0

    /// Cached maps — invalidated on revision bump to avoid repeated full table scans.
    @ObservationIgnored private var cachedArtistMap: [UUID: LibraryArtist]?
    @ObservationIgnored private var cachedAlbumMap: [UUID: LibraryAlbum]?

    /// Track IDs whose download state changed. Views observe this to update in-place
    /// without re-querying SwiftData.
    private(set) var downloadChanged: Set<UUID> = []

    /// Updates `isDownloaded` in-place on tracks affected by the latest download change.
    func applyDownloadChanges(to tracks: inout [Track]) {
        for i in tracks.indices where downloadChanged.contains(tracks[i].id) {
            tracks[i].isDownloaded = isDownloaded(trackId: tracks[i].id)
        }
    }

    /// Internal init for testing — accepts a pre-built container (e.g. in-memory).
    init(container: ModelContainer) {
        self.modelContainer = container
    }

    init() throws {
        let schema = Schema([LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
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
        let descriptor = FetchDescriptor<LibraryArtist>(
            predicate: #Predicate { $0.albumCount > 0 },
            sortBy: [SortDescriptor(\.sortName)]
        )
        let libArtists = (try? modelContext.fetch(descriptor)) ?? []
        return libArtists.map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName,
                   slug: $0.slug, albumCount: $0.albumCount)
        }
    }

    func artist(_ id: UUID) -> Artist? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryArtist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = try? modelContext.fetch(descriptor).first else { return nil }
        return Artist(id: la.serverId, name: la.name, sortName: la.sortName, slug: la.slug, albumCount: la.albumCount)
    }

    // MARK: - Query: Albums

    func allAlbums() -> [Album] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.trackCount > 0 })
        let libAlbums = (try? modelContext.fetch(descriptor)) ?? []
        let artistMap = buildArtistMap()
        return libAlbums.map { toAlbum($0, artistMap: artistMap) }
    }

    func albumsForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.artistId == artistId })
        let libAlbums = (try? modelContext.fetch(descriptor)) ?? []
        return libAlbums
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
            .map { toAlbum($0) }
    }

    func album(_ id: UUID) -> Album? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = try? modelContext.fetch(descriptor).first else { return nil }
        return toAlbum(la)
    }

    func track(_ id: UUID) -> Track? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let lt = try? modelContext.fetch(descriptor).first else { return nil }
        let artist = fetchArtist(lt.artistId)
        let album = fetchAlbum(lt.albumId)
        let albumArtist = lt.albumArtistId != lt.artistId ? fetchArtist(lt.albumArtistId) : artist
        return buildTrack(lt, artist: artist, albumArtist: albumArtist, album: album)
    }

    func albumWithTracks(_ id: UUID) -> Album? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = try? modelContext.fetch(descriptor).first else { return nil }
        let tracks = tracksForAlbum(id)
        return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
                     slug: la.slug, releaseYear: la.releaseYear, tracks: tracks,
                     isUnknown: la.isUnknown, artworkUrl: la.artworkUrl)
    }

    func albumsWithTracksForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        let albumDescriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.artistId == artistId })
        let libAlbums = ((try? modelContext.fetch(albumDescriptor)) ?? [])
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }

        let trackDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId })
        let libTracks = (try? modelContext.fetch(trackDescriptor)) ?? []

        let artistMap = buildArtistMapForIds(Set(libTracks.map(\.artistId) + [artistId]))
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
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId })
        let libTracks = (try? modelContext.fetch(descriptor)) ?? []
        let artistIds = Set(libTracks.map(\.artistId) + libTracks.map(\.albumArtistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let album = fetchAlbumRecord(albumId)
        return libTracks
            .map { buildTrack($0, artistMap: artistMap, album: album) }
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

        let artists = (try? modelContext.fetch(FetchDescriptor<LibraryArtist>())) ?? []
        let filteredArtists = artists
            .filter { $0.name.localizedCaseInsensitiveContains(query) || $0.sortName.localizedCaseInsensitiveContains(query) }
            .filter { $0.albumCount > 0 }
            .sorted { $0.sortName < $1.sortName }
            .map { Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount) }

        let albums = (try? modelContext.fetch(FetchDescriptor<LibraryAlbum>())) ?? []
        let filteredAlbums = albums
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
        let allTracks = (try? modelContext.fetch(FetchDescriptor<LibraryTrack>())) ?? []
        let filteredTracks = allTracks
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .map { buildTrack($0, artistMap: artistMap, album: albumMap[$0.albumId]) }
            .sorted { ($0.artist.sortName, $0.name) < ($1.artist.sortName, $1.name) }

        return (filteredArtists, filteredAlbums, filteredTracks)
    }

    // MARK: - Downloads

    func isDownloaded(trackId: UUID) -> Bool {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func downloadedTrackCount(albumId: UUID) -> Int {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func isAlbumDownloaded(albumId: UUID) -> Bool {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func isAlbumFullyDownloaded(albumId: UUID) -> Bool {
        _ = downloadChanged
        let allDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId })
        let downloadedDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        let total = (try? modelContext.fetchCount(allDescriptor)) ?? 0
        let downloaded = (try? modelContext.fetchCount(downloadedDescriptor)) ?? 0
        return total > 0 && total == downloaded
    }

    func isArtistDownloaded(artistId: UUID) -> Bool {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func isArtistFullyDownloaded(artistId: UUID) -> Bool {
        _ = downloadChanged
        let allDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId })
        let downloadedDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        let total = (try? modelContext.fetchCount(allDescriptor)) ?? 0
        let downloaded = (try? modelContext.fetchCount(downloadedDescriptor)) ?? 0
        return total > 0 && total == downloaded
    }

    func downloadedSize() -> Int64 {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        return tracks.reduce(0) { $0 + ($1.downloadedFileSize > 0 ? $1.downloadedFileSize : $1.fileSize) }
    }

    func downloadedSize(artistId: UUID) -> Int64 {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        return tracks.reduce(0) { $0 + ($1.downloadedFileSize > 0 ? $1.downloadedFileSize : $1.fileSize) }
    }

    func localURL(for trackId: UUID) -> URL? {
        _ = downloadChanged
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId && $0.isDownloaded == true })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return nil }
        return track.resolvedFileURL
    }

    /// Returns artists that have at least one downloaded track, sorted by sortName.
    func downloadedArtists() -> [Artist] {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        let downloaded = (try? modelContext.fetch(descriptor)) ?? []
        let artistIds = Set(downloaded.map(\.albumArtistId))
        let artistMap = buildArtistMapForIds(artistIds)
        return artistIds.compactMap { id in
            guard let la = artistMap[id] else { return nil }
            let downloadedAlbumIds = Set(downloaded.filter { $0.albumArtistId == id }.map(\.albumId))
            return Artist(id: la.serverId, name: la.name, sortName: la.sortName,
                          slug: la.slug, albumCount: downloadedAlbumIds.count)
        }.sorted { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }
    }

    /// Returns all albums that have at least one downloaded track.
    func downloadedAlbums() -> [Album] {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        let downloaded = (try? modelContext.fetch(descriptor)) ?? []
        let albumIds = Set(downloaded.map(\.albumId))
        let artistMap = buildArtistMap()
        let albumDescriptor = FetchDescriptor<LibraryAlbum>()
        return ((try? modelContext.fetch(albumDescriptor)) ?? [])
            .filter { albumIds.contains($0.serverId) }
            .map { toAlbum($0, artistMap: artistMap) }
    }

    /// Returns all downloaded tracks, sorted like allTracks().
    func downloadedTracks() -> [Track] {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        let libTracks = (try? modelContext.fetch(descriptor)) ?? []
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
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true && $0.albumArtistId == artistId })
        let downloaded = (try? modelContext.fetch(descriptor)) ?? []
        let albumIds = Set(downloaded.map(\.albumId))
        let artistMap = buildArtistMapForIds([artistId])
        let albumDescriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.artistId == artistId })
        return ((try? modelContext.fetch(albumDescriptor)) ?? [])
            .filter { albumIds.contains($0.serverId) }
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
            .map { toAlbum($0, artistMap: artistMap) }
    }

    func markDownloaded(trackId: UUID, relativePath: String, downloadedFileSize: Int64 = 0) {
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        track.isDownloaded = true
        track.localFilePath = relativePath
        track.downloadedFileSize = downloadedFileSize
        try? modelContext.save()
        downloadChanged = [trackId]
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
        downloadChanged = [trackId]
    }

    func markAlbumUndownloaded(albumId: UUID) {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed = Set<UUID>()
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed.insert(track.serverId)
        }
        try? modelContext.save()
        downloadChanged = changed
    }

    func markArtistUndownloaded(artistId: UUID) {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed = Set<UUID>()
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed.insert(track.serverId)
        }
        try? modelContext.save()
        downloadChanged = changed
    }

    func markAllUndownloaded() {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed = Set<UUID>()
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed.insert(track.serverId)
        }
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let downloadsDir = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            try? fm.removeItem(at: downloadsDir)
        }
        try? modelContext.save()
        downloadChanged = changed
    }

    func downloadedFileURLs(albumId: UUID) -> [URL] {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return [] }
        return tracks.compactMap(\.resolvedFileURL)
    }

    func downloadedFileURLs(artistId: UUID) -> [URL] {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return [] }
        return tracks.compactMap(\.resolvedFileURL)
    }

    func availableTracks(_ tracks: [Track], isOnline: Bool) -> [Track] {
        if isOnline { return tracks }
        return tracks.filter { $0.isDownloaded }
    }

    func availableItems(_ items: [QueueItem], isOnline: Bool) -> [QueueItem] {
        if isOnline { return items }
        return items.filter { $0.track.isDownloaded }
    }

    // MARK: - Mutations (called by SyncService)

    func bumpRevision() {
        cachedArtistMap = nil
        cachedAlbumMap = nil
        revision += 1
    }

    func upsertArtists(_ syncArtists: [SyncArtist]) {
        guard !syncArtists.isEmpty else { return }
        let ids = syncArtists.map(\.id)
        let descriptor = FetchDescriptor<LibraryArtist>(predicate: #Predicate { ids.contains($0.serverId) })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
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
    }

    /// Returns the server IDs of newly inserted albums.
    @discardableResult
    func upsertAlbums(_ syncAlbums: [SyncAlbum]) -> Set<UUID> {
        guard !syncAlbums.isEmpty else { return [] }
        let ids = syncAlbums.map(\.id)
        let descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { ids.contains($0.serverId) })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        var inserted = Set<UUID>()
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
                inserted.insert(sa.id)
            }
        }
        try? modelContext.save()
        return inserted
    }

    func upsertTracks(_ syncTracks: [SyncTrack]) {
        guard !syncTracks.isEmpty else { return }
        let ids = syncTracks.map(\.id)
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { ids.contains($0.serverId) })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
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
                lt.downloadUrl = st.downloadUrl
                lt.insertedAt = st.insertedAt
                lt.fileSize = st.file.size
                lt.fileChecksum = st.file.checksum
            } else {
                modelContext.insert(LibraryTrack(
                    serverId: st.id, artistId: st.artistId, albumArtistId: st.albumArtistId,
                    albumId: st.albumId, name: st.name, disc: st.disc, number: st.number,
                    duration: st.duration, mimetype: st.mimetype, streamUrl: st.streamUrl,
                    downloadUrl: st.downloadUrl, insertedAt: st.insertedAt,
                    fileSize: st.file.size, fileChecksum: st.file.checksum))
            }
        }
        try? modelContext.save()
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
                var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == id })
                descriptor.fetchLimit = 1
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
    }

    func clearAll() {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let downloadsDir = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            try? fm.removeItem(at: downloadsDir)
        }
        try? modelContext.delete(model: LibraryTrack.self)
        try? modelContext.delete(model: LibraryAlbum.self)
        try? modelContext.delete(model: LibraryArtist.self)
        try? modelContext.save()
        cachedArtistMap = nil
        cachedAlbumMap = nil
        revision += 1
    }

    // MARK: - Private: Targeted Fetches

    private func fetchArtist(_ id: UUID) -> LibraryArtist? {
        var descriptor = FetchDescriptor<LibraryArtist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchAlbum(_ id: UUID) -> Album? {
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = try? modelContext.fetch(descriptor).first else { return nil }
        return toAlbum(la)
    }

    private func fetchAlbumRecord(_ id: UUID) -> LibraryAlbum? {
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Build artist map for a specific set of IDs (avoids full table scan when few IDs needed).
    private func buildArtistMapForIds(_ ids: Set<UUID>) -> [UUID: LibraryArtist] {
        // For small sets, targeted fetches; for large sets, full scan is faster
        if ids.count <= 10 {
            var map: [UUID: LibraryArtist] = [:]
            for id in ids {
                if let artist = fetchArtist(id) {
                    map[id] = artist
                }
            }
            return map
        }
        return buildArtistMap()
    }

    /// Full artist map — cached between revision bumps.
    private func buildArtistMap() -> [UUID: LibraryArtist] {
        if let cached = cachedArtistMap { return cached }
        let artists = (try? modelContext.fetch(FetchDescriptor<LibraryArtist>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: artists.map { ($0.serverId, $0) })
        cachedArtistMap = map
        return map
    }

    /// Full album map — cached between revision bumps.
    private func buildAlbumMap() -> [UUID: LibraryAlbum] {
        if let cached = cachedAlbumMap { return cached }
        let albums = (try? modelContext.fetch(FetchDescriptor<LibraryAlbum>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: albums.map { ($0.serverId, $0) })
        cachedAlbumMap = map
        return map
    }

    // MARK: - Private: Builders

    private func toAlbum(_ la: LibraryAlbum, artistMap: [UUID: LibraryArtist]? = nil) -> Album {
        let artist = artistMap?[la.artistId]
        return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
              slug: la.slug, releaseYear: la.releaseYear, isUnknown: la.isUnknown,
              artworkUrl: la.artworkUrl, insertedAt: la.insertedAt,
              artistName: artist?.name, artistSortName: artist?.sortName)
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
            mimetype: lt.mimetype, streamUrl: lt.streamUrl, downloadUrl: lt.downloadUrl,
            fileSize: lt.fileSize, isDownloaded: lt.isDownloaded
        )
    }

    /// Build a Track from individually-fetched entities (for single-track lookups).
    private func buildTrack(_ lt: LibraryTrack, artist: LibraryArtist?, albumArtist: LibraryArtist?, album: Album?) -> Track {
        let artistModel = artist.map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount)
        } ?? Artist(id: lt.artistId, name: "Unknown", sortName: "Unknown", slug: "unknown")

        let trackAlbum = album.map {
            Track.TrackAlbum(id: $0.id, name: $0.name, artworkUrl: $0.artworkUrl)
        }

        let albumArtistSortName = albumArtist?.sortName ?? artistModel.sortName

        return Track(
            id: lt.serverId, artistId: lt.artistId, albumArtistId: lt.albumArtistId,
            albumId: lt.albumId, artist: artistModel, albumArtistSortName: albumArtistSortName,
            album: trackAlbum, name: lt.name,
            disc: lt.disc, number: lt.number, duration: lt.duration,
            mimetype: lt.mimetype, streamUrl: lt.streamUrl, downloadUrl: lt.downloadUrl,
            fileSize: lt.fileSize, isDownloaded: lt.isDownloaded
        )
    }

    // MARK: - Private: Cascade Deletes

    private func deleteArtistCascade(_ artistId: UUID) {
        let trackDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.artistId == artistId })
        for track in (try? modelContext.fetch(trackDescriptor)) ?? [] {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(track)
        }
        let albumDescriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.artistId == artistId })
        for album in (try? modelContext.fetch(albumDescriptor)) ?? [] {
            modelContext.delete(album)
        }
        if let artist = fetchArtist(artistId) {
            modelContext.delete(artist)
        }
    }

    private func deleteAlbumCascade(_ albumId: UUID) {
        let trackDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId })
        for track in (try? modelContext.fetch(trackDescriptor)) ?? [] {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(track)
        }
        if let album = fetchAlbumRecord(albumId) {
            modelContext.delete(album)
        }
    }
}
