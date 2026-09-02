import Foundation
import SwiftData

nonisolated struct TrackGroupKey: Hashable {
    let albumArtistId: UUID
    let albumId: UUID
}

@Observable
final class MusicLibrary {
    @ObservationIgnored let modelContainer: ModelContainer

    /// Incremented on content mutations (sync, clear) so views that read it re-evaluate.
    var revision: UInt = 0

    /// Cached maps — invalidated on revision bump to avoid repeated full table scans.
    @ObservationIgnored var cachedArtistMap: [UUID: LibraryArtist]?
    @ObservationIgnored var cachedAlbumMap: [UUID: LibraryAlbum]?

    /// Cached result of `allTracks()`. Every navigation to the Songs list re-runs the
    /// whole fetch-and-sort, which is the single most expensive query in the app at
    /// library scale. Invalidated with the maps; download mutations patch it in place.
    @ObservationIgnored var cachedAllTracks: [Track]?

    /// Track IDs whose download state changed, mapped to the new `isDownloaded` value.
    /// Views observe this to update in-place without re-querying SwiftData.
    var downloadChanged: [UUID: Bool] = [:]

    /// Updates `isDownloaded` in-place on tracks affected by the latest download change.
    func applyDownloadChanges(to tracks: inout [Track]) {
        for i in tracks.indices {
            if let newState = downloadChanged[tracks[i].id] {
                tracks[i].isDownloaded = newState
            }
        }
    }

    /// Internal init for testing — accepts a pre-built container (e.g. in-memory).
    init(container: ModelContainer) {
        self.modelContainer = container
    }

    init() throws {
        let schema = Schema([LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self, LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            #if DEBUG
            print("MusicLibrary: schema migration failed, resetting database: \(error)")
            #endif
            // Scan the Downloads/ directory and record what's on disk BEFORE we wipe the
            // SwiftData store. After a successful re-sync, reconcileDownloadedFiles() uses
            // this manifest to re-mark tracks as downloaded (and delete orphaned files).
            Self.writeReconciliationManifest()
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

    // MARK: - Reconciliation manifest

    nonisolated struct DownloadManifestEntry: Codable, Sendable {
        let trackId: UUID
        let relativePath: String
        let fileSize: Int64
    }

    nonisolated static var reconciliationManifestURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent("MusicBox/.reconciliation-manifest.json")
    }

    /// Scans Downloads/{artistId}/{albumId}/{trackId}.ext and writes a manifest of found files.
    /// Called from the store-reset catch path so we can rebuild download state after sync.
    nonisolated static func writeReconciliationManifest() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let downloads = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
        guard fm.fileExists(atPath: downloads.path) else { return }

        var entries: [DownloadManifestEntry] = []
        let enumerator = fm.enumerator(at: downloads, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let trackIdString = url.deletingPathExtension().lastPathComponent
            guard let trackId = UUID(uuidString: trackIdString) else { continue }
            let relativePath = "MusicBox/Downloads/\(url.path.replacingOccurrences(of: downloads.path + "/", with: ""))"
            let size = Int64(values?.fileSize ?? 0)
            entries.append(DownloadManifestEntry(trackId: trackId, relativePath: relativePath, fileSize: size))
        }

        guard let manifestURL = reconciliationManifestURL else { return }
        try? fm.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: manifestURL)
    }

    var modelContext: ModelContext { modelContainer.mainContext }

    func persistChanges(_ caller: String = #function) {
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("MusicLibrary: save failed in \(caller): \(error)")
            #endif
        }
    }

    /// Fetches with debug logging on failure. In release builds, silently returns nil.
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, caller: String = #function) -> [T]? {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            #if DEBUG
            print("MusicLibrary: fetch failed in \(caller): \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Query: Artists

    func allArtists() -> [Artist] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryArtist>(
            predicate: #Predicate { $0.albumCount > 0 },
            sortBy: [SortDescriptor(\.sortName)]
        )
        let libArtists = fetch(descriptor) ?? []
        return libArtists.map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName,
                   slug: $0.slug, albumCount: $0.albumCount)
        }
    }

    func artist(_ id: UUID) -> Artist? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryArtist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = fetch(descriptor)?.first else { return nil }
        return Artist(id: la.serverId, name: la.name, sortName: la.sortName, slug: la.slug, albumCount: la.albumCount)
    }

    // MARK: - Query: Albums

    func allAlbums() -> [Album] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.trackCount > 0 })
        let libAlbums = fetch(descriptor) ?? []
        let artistMap = buildArtistMap()
        return libAlbums.map { toAlbum($0, artistMap: artistMap) }
    }

    func albumsForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.artistId == artistId })
        let libAlbums = fetch(descriptor) ?? []
        return libAlbums
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
            .map { toAlbum($0) }
    }

    func album(_ id: UUID) -> Album? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = fetch(descriptor)?.first else { return nil }
        return toAlbum(la)
    }

    func track(_ id: UUID) -> Track? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let lt = fetch(descriptor)?.first else { return nil }
        let artist = fetchArtist(lt.artistId)
        let album = fetchAlbum(lt.albumId)
        let albumArtist = lt.albumArtistId != lt.artistId ? fetchArtist(lt.albumArtistId) : artist
        return buildTrack(lt, artist: artist, albumArtist: albumArtist, album: album)
    }

    func albumWithTracks(_ id: UUID) -> Album? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = fetch(descriptor)?.first else { return nil }
        let tracks = tracksForAlbum(id)
        return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
                     slug: la.slug, releaseYear: la.releaseYear, tracks: tracks,
                     isUnknown: la.isUnknown, artworkUrl: la.artworkUrl)
    }

    func albumsWithTracksForArtist(_ artistId: UUID) -> [Album] {
        _ = revision
        let albumDescriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.artistId == artistId })
        let libAlbums = (fetch(albumDescriptor) ?? [])
            .sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }

        let trackDescriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId })
        let libTracks = fetch(trackDescriptor) ?? []

        let artistMap = buildArtistMapForIds(Set(libTracks.map(\.artistId) + [artistId]))
        let tracksByAlbum = Dictionary(grouping: libTracks, by: \.albumId)

        return libAlbums.map { la in
            let albumTracks = (tracksByAlbum[la.serverId] ?? [])
                .map { buildTrack($0, artistMap: artistMap, album: la) }
                .sorted { ($0.disc, $0.number ?? Int.max) < ($1.disc, $1.number ?? Int.max) }
            return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
                         slug: la.slug, releaseYear: la.releaseYear, tracks: albumTracks,
                         isUnknown: la.isUnknown, artworkUrl: la.artworkUrl)
        }
    }

    // MARK: - Query: Tracks

    /// Resolves many tracks in one fetch, keyed by id. Restoring a saved queue used to
    /// call `track(_:)` per id — a fetch each, plus an artist and album lookup each —
    /// which put hundreds of round trips on the main thread during launch.
    func tracks(ids: [UUID]) -> [UUID: Track] {
        _ = revision
        guard !ids.isEmpty else { return [:] }
        let wanted = Array(Set(ids))
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { wanted.contains($0.serverId) })
        let libTracks = fetch(descriptor) ?? []
        let artistIds = Set(libTracks.map(\.artistId) + libTracks.map(\.albumArtistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let albumMap = buildAlbumMap()
        var byId: [UUID: Track] = [:]
        for lt in libTracks {
            byId[lt.serverId] = buildTrack(lt, artistMap: artistMap, album: albumMap[lt.albumId])
        }
        return byId
    }

    func tracksForAlbum(_ albumId: UUID) -> [Track] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId })
        let libTracks = fetch(descriptor) ?? []
        let artistIds = Set(libTracks.map(\.artistId) + libTracks.map(\.albumArtistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let album = fetchAlbumRecord(albumId)
        return libTracks
            .map { buildTrack($0, artistMap: artistMap, album: album) }
            .sorted { ($0.disc, $0.number ?? Int.max) < ($1.disc, $1.number ?? Int.max) }
    }

    /// Sorted per album rather than per track. The flat comparator paid four dictionary
    /// lookups plus a localized collation on every one of ~n log n comparisons, even
    /// though every track in an album shares both string keys — at library scale that
    /// collation dominated the whole call.
    nonisolated static func sortedTracks(_ libTracks: [LibraryTrack],
                                         artistMap: [UUID: LibraryArtist],
                                         albumMap: [UUID: LibraryAlbum]) -> [Track] {
        var groups: [TrackGroupKey: [LibraryTrack]] = [:]
        for lt in libTracks {
            groups[TrackGroupKey(albumArtistId: lt.albumArtistId, albumId: lt.albumId), default: []].append(lt)
        }
        let orderedKeys = groups.keys.sorted { a, b in
            let aArtist = artistMap[a.albumArtistId]?.sortName ?? ""
            let bArtist = artistMap[b.albumArtistId]?.sortName ?? ""
            if aArtist != bArtist { return aArtist < bArtist }
            let aAlbum = albumMap[a.albumId]?.sortName ?? ""
            let bAlbum = albumMap[b.albumId]?.sortName ?? ""
            return aAlbum.localizedStandardCompare(bAlbum) == .orderedAscending
        }

        var result: [Track] = []
        result.reserveCapacity(libTracks.count)
        for key in orderedKeys {
            let album = albumMap[key.albumId]
            let ordered = (groups[key] ?? []).sorted {
                if $0.disc != $1.disc { return $0.disc < $1.disc }
                return ($0.number ?? Int.max) < ($1.number ?? Int.max)
            }
            for lt in ordered { result.append(buildTrackValue(lt, artistMap: artistMap, album: album)) }
        }
        return result
    }

    /// Rebuilds the tracks cache on a background context and installs it.
    ///
    /// `allTracks()` stays synchronous for callers that need it now, but on a slower Mac
    /// its fetch-and-build is long enough to read as a hang when it lands on a click.
    /// Doing it here — after a sync, or before the Songs list is first opened — keeps
    /// that work off whoever happens to tap next.
    func prepareAllTracks() async {
        let container = modelContainer
        let built = await Task.detached {
            let context = ModelContext(container)
            guard let libTracks = try? context.fetch(FetchDescriptor<LibraryTrack>()),
                  let libArtists = try? context.fetch(FetchDescriptor<LibraryArtist>()),
                  let libAlbums = try? context.fetch(FetchDescriptor<LibraryAlbum>())
            else { return [Track]() }
            let artistMap = Dictionary(uniqueKeysWithValues: libArtists.map { ($0.serverId, $0) })
            let albumMap = Dictionary(uniqueKeysWithValues: libAlbums.map { ($0.serverId, $0) })
            return Self.sortedTracks(libTracks, artistMap: artistMap, albumMap: albumMap)
        }.value
        cachedAllTracks = built
    }

    func allTracks() -> [Track] {
        _ = revision
        if let cachedAllTracks { return cachedAllTracks }
        let libTracks = fetch(FetchDescriptor<LibraryTrack>()) ?? []
        let artistMap = buildArtistMap()
        let albumMap = buildAlbumMap()

        let result = Self.sortedTracks(libTracks, artistMap: artistMap, albumMap: albumMap)
        cachedAllTracks = result
        return result
    }

    // MARK: - Query: Playlists

    /// All playlists and folders, alphabetical. Used by views that ignore hierarchy
    /// (e.g. AddToPlaylistSheet — there we further filter out folders client-side).
    func allPlaylists() -> [Playlist] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryPlaylist>(
            sortBy: [SortDescriptor(\.name, comparator: .localizedStandard)]
        )
        return (fetch(descriptor) ?? []).map(toPlaylist)
    }

    /// Children of `parentId` (nil = root). Folders sorted before playlists, then alphabetical.
    func playlists(in parentId: UUID?) -> [Playlist] {
        _ = revision
        let descriptor: FetchDescriptor<LibraryPlaylist>
        if let parentId {
            descriptor = FetchDescriptor<LibraryPlaylist>(
                predicate: #Predicate { $0.parentId == parentId }
            )
        } else {
            descriptor = FetchDescriptor<LibraryPlaylist>(
                predicate: #Predicate { $0.parentId == nil }
            )
        }
        let entries = (fetch(descriptor) ?? []).map(toPlaylist)
        return entries.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder && !b.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Number of direct children of a folder — used to render "n items" in folder rows.
    func childCount(of parentId: UUID) -> Int {
        _ = revision
        let descriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.parentId == parentId }
        )
        return (fetch(descriptor) ?? []).count
    }

    func playlist(_ id: UUID) -> Playlist? {
        _ = revision
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let lp = fetch(descriptor)?.first else { return nil }
        return toPlaylist(lp)
    }

    private func toPlaylist(_ lp: LibraryPlaylist) -> Playlist {
        Playlist(id: lp.serverId, name: lp.name, trackCount: lp.trackCount,
                 insertedAt: lp.insertedAt, isFolder: lp.isFolder, parentId: lp.parentId,
                 autoDownload: lp.autoDownload)
    }

    /// Flips a playlist's `autoDownload` flag. Caller is responsible for triggering any
    /// backfill or cleanup downloads as appropriate.
    func setPlaylistAutoDownload(id: UUID, enabled: Bool) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let lp = fetch(descriptor)?.first else { return }
        lp.autoDownload = enabled
        persistChanges()
        revision += 1
    }

    /// Set of track IDs that live in an `autoDownload`-flagged playlist and aren't yet downloaded.
    /// Called by SyncService after each sync so new items or backfill tracks get queued for download.
    func tracksNeedingAutoDownload() -> Set<UUID> {
        _ = revision
        let playlistDescriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.autoDownload == true }
        )
        let autoPlaylists = fetch(playlistDescriptor) ?? []
        guard !autoPlaylists.isEmpty else { return [] }
        let playlistIds = Set(autoPlaylists.map(\.serverId))
        let itemDescriptor = FetchDescriptor<LibraryPlaylistItem>(
            predicate: #Predicate { playlistIds.contains($0.playlistId) }
        )
        let items = fetch(itemDescriptor) ?? []
        let candidateTrackIds = Set(items.map(\.trackId))
        guard !candidateTrackIds.isEmpty else { return [] }
        let trackDescriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { candidateTrackIds.contains($0.serverId) && $0.isDownloaded == false }
        )
        let tracks = fetch(trackDescriptor) ?? []
        return Set(tracks.map(\.serverId))
    }

    func playlistItems(_ playlistId: UUID) -> [PlaylistItem] {
        _ = revision
        let descriptor = FetchDescriptor<LibraryPlaylistItem>(
            predicate: #Predicate { $0.playlistId == playlistId },
            sortBy: [SortDescriptor(\.position)]
        )
        return (fetch(descriptor) ?? []).map {
            PlaylistItem(id: $0.serverId, playlistId: $0.playlistId, trackId: $0.trackId,
                         position: $0.position, insertedAt: $0.insertedAt)
        }
    }

    /// Returns tracks for a playlist in `position` order. Items whose track is missing from the library
    /// are silently skipped (e.g. after a cascade delete of the underlying track).
    func tracksForPlaylist(_ playlistId: UUID) -> [Track] {
        _ = revision
        let itemDescriptor = FetchDescriptor<LibraryPlaylistItem>(
            predicate: #Predicate { $0.playlistId == playlistId },
            sortBy: [SortDescriptor(\.position)]
        )
        let items = fetch(itemDescriptor) ?? []
        guard !items.isEmpty else { return [] }

        let trackIds = items.map(\.trackId)
        let trackDescriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { trackIds.contains($0.serverId) }
        )
        let libTracks = fetch(trackDescriptor) ?? []
        let trackMap = Dictionary(uniqueKeysWithValues: libTracks.map { ($0.serverId, $0) })

        let artistIds = Set(libTracks.map(\.artistId) + libTracks.map(\.albumArtistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let albumIds = Set(libTracks.map(\.albumId))
        let albumMap: [UUID: LibraryAlbum]
        if albumIds.count <= 20 {
            var map: [UUID: LibraryAlbum] = [:]
            for id in albumIds {
                if let album = fetchAlbumRecord(id) { map[id] = album }
            }
            albumMap = map
        } else {
            albumMap = buildAlbumMap()
        }

        return items.compactMap { item in
            guard let lt = trackMap[item.trackId] else { return nil }
            return buildTrack(lt, artistMap: artistMap, album: albumMap[lt.albumId])
        }
    }

    // MARK: - Search

    /// Artists carry no artwork of their own, so each borrows its first album's. Resolved
    /// in one pass for a set of search results rather than per row.
    func artistArtwork(for artists: [Artist]) -> [UUID: URL] {
        _ = revision
        return Dictionary(uniqueKeysWithValues: artists.compactMap { artist in
            albumsForArtist(artist.id)
                .first(where: { $0.artworkUrl != nil })
                .flatMap(\.artworkUrl)
                .map { (artist.id, $0) }
        })
    }

    func search(_ query: String) -> (artists: [Artist], albums: [Album], tracks: [Track]) {
        _ = revision
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return ([], [], []) }

        let artistDescriptor = FetchDescriptor<LibraryArtist>(
            predicate: #Predicate {
                $0.albumCount > 0 && (
                    $0.name.localizedStandardContains(query) ||
                    $0.sortName.localizedStandardContains(query)
                )
            },
            sortBy: [SortDescriptor(\.sortName)]
        )
        let matchedArtists = fetch(artistDescriptor) ?? []
        let filteredArtists = matchedArtists.map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount)
        }

        // An album matches on its own name or by belonging to a matched artist, so
        // searching an artist's name returns their discography rather than only the
        // albums with that word in the title.
        let matchedArtistIds = matchedArtists.map(\.serverId)
        let albumDescriptor = FetchDescriptor<LibraryAlbum>(
            predicate: #Predicate {
                $0.trackCount > 0 && (
                    $0.name.localizedStandardContains(query) ||
                    $0.sortName.localizedStandardContains(query) ||
                    matchedArtistIds.contains($0.artistId)
                )
            }
        )
        let matchedAlbums = fetch(albumDescriptor) ?? []
        let artistIds = Set(matchedAlbums.map(\.artistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let filteredAlbums = matchedAlbums
            .sorted { a, b in
                let aName = a.name.localizedStandardContains(query)
                let bName = b.name.localizedStandardContains(query)
                if aName != bName { return aName }
                let aSortName = artistMap[a.artistId]?.sortName ?? ""
                let bSortName = artistMap[b.artistId]?.sortName ?? ""
                if aSortName != bSortName { return aSortName < bSortName }
                let aYear = a.releaseYear ?? 0
                let bYear = b.releaseYear ?? 0
                if aYear != bYear { return aYear > bYear }
                return a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
            }
            .map { toAlbum($0, artistMap: artistMap) }

        // A track matches on its own title or by belonging to a matched artist or album,
        // so searching an artist's name lists their songs rather than an empty Songs
        // section. SwiftData can't join, so the ids matched above are folded in instead.
        let matchedAlbumIds = matchedAlbums.map(\.serverId)
        let trackDescriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(query) ||
                matchedArtistIds.contains($0.artistId) ||
                matchedArtistIds.contains($0.albumArtistId) ||
                matchedAlbumIds.contains($0.albumId)
            }
        )
        let matchedTracks = fetch(trackDescriptor) ?? []
        let trackArtistIds = Set(matchedTracks.map(\.artistId) + matchedTracks.map(\.albumArtistId))
        let trackArtistMap = buildArtistMapForIds(trackArtistIds)
        let trackAlbumIds = Set(matchedTracks.map(\.albumId))
        let trackAlbumMap: [UUID: LibraryAlbum]
        if trackAlbumIds.count <= 20 {
            var map: [UUID: LibraryAlbum] = [:]
            for id in trackAlbumIds {
                if let album = fetchAlbumRecord(id) { map[id] = album }
            }
            trackAlbumMap = map
        } else {
            trackAlbumMap = buildAlbumMap()
        }
        // Title matches rank above tracks that only matched through their artist or
        // album — typing a song name should not bury it under that artist's discography.
        let filteredTracks = matchedTracks
            .map { buildTrack($0, artistMap: trackArtistMap, album: trackAlbumMap[$0.albumId]) }
            .sorted { a, b in
                let aTitle = a.name.localizedStandardContains(query)
                let bTitle = b.name.localizedStandardContains(query)
                if aTitle != bTitle { return aTitle }
                return (a.artist.sortName, a.name) < (b.artist.sortName, b.name)
            }

        return (filteredArtists, filteredAlbums, filteredTracks)
    }

    // MARK: - Internal: Targeted Fetches

    func fetchArtist(_ id: UUID) -> LibraryArtist? {
        var descriptor = FetchDescriptor<LibraryArtist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor)?.first
    }

    func fetchAlbum(_ id: UUID) -> Album? {
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let la = fetch(descriptor)?.first else { return nil }
        return toAlbum(la)
    }

    func fetchAlbumRecord(_ id: UUID) -> LibraryAlbum? {
        var descriptor = FetchDescriptor<LibraryAlbum>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor)?.first
    }

    /// Build artist map for a specific set of IDs (avoids full table scan when few IDs needed).
    func buildArtistMapForIds(_ ids: Set<UUID>) -> [UUID: LibraryArtist] {
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
    func buildArtistMap() -> [UUID: LibraryArtist] {
        if let cached = cachedArtistMap { return cached }
        let artists = fetch(FetchDescriptor<LibraryArtist>()) ?? []
        let map = Dictionary(uniqueKeysWithValues: artists.map { ($0.serverId, $0) })
        cachedArtistMap = map
        return map
    }

    /// Full album map — cached between revision bumps.
    func buildAlbumMap() -> [UUID: LibraryAlbum] {
        if let cached = cachedAlbumMap { return cached }
        let albums = fetch(FetchDescriptor<LibraryAlbum>()) ?? []
        let map = Dictionary(uniqueKeysWithValues: albums.map { ($0.serverId, $0) })
        cachedAlbumMap = map
        return map
    }

    // MARK: - Internal: Builders

    func toAlbum(_ la: LibraryAlbum, artistMap: [UUID: LibraryArtist]? = nil) -> Album {
        let artist = artistMap?[la.artistId]
        return Album(id: la.serverId, artistId: la.artistId, name: la.name, sortName: la.sortName,
              slug: la.slug, releaseYear: la.releaseYear, isUnknown: la.isUnknown,
              artworkUrl: la.artworkUrl, insertedAt: la.insertedAt,
              artistName: artist?.name, artistSortName: artist?.sortName)
    }

    func buildTrack(_ lt: LibraryTrack, artistMap: [UUID: LibraryArtist], album: LibraryAlbum?) -> Track {
        Self.buildTrackValue(lt, artistMap: artistMap, album: album)
    }

    /// Same construction, callable from the background rebuild — model objects are read
    /// through whichever context fetched them, and nothing here touches the main one.
    nonisolated static func buildTrackValue(_ lt: LibraryTrack, artistMap: [UUID: LibraryArtist], album: LibraryAlbum?) -> Track {
        let artist = artistMap[lt.artistId].map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount)
        } ?? Artist(id: lt.artistId, name: "Unknown", sortName: "Unknown", slug: "unknown")

        let trackAlbum = album.map {
            Track.TrackAlbum(id: $0.serverId, name: $0.name, artworkUrl: $0.artworkUrl)
        }

        let albumArtistName = artistMap[lt.albumArtistId]?.name ?? artist.name
        let albumArtistSortName = artistMap[lt.albumArtistId]?.sortName ?? artist.sortName

        return Track(
            id: lt.serverId, artistId: lt.artistId, albumArtistId: lt.albumArtistId,
            albumId: lt.albumId, artist: artist,
            albumArtistName: albumArtistName, albumArtistSortName: albumArtistSortName,
            album: trackAlbum, name: lt.name,
            disc: lt.disc, number: lt.number, duration: lt.duration,
            mimetype: lt.mimetype, streamUrl: lt.streamUrl, downloadUrl: lt.downloadUrl,
            isDownloaded: lt.isDownloaded
        )
    }

    /// Build a Track from individually-fetched entities (for single-track lookups).
    func buildTrack(_ lt: LibraryTrack, artist: LibraryArtist?, albumArtist: LibraryArtist?, album: Album?) -> Track {
        let artistModel = artist.map {
            Artist(id: $0.serverId, name: $0.name, sortName: $0.sortName, slug: $0.slug, albumCount: $0.albumCount)
        } ?? Artist(id: lt.artistId, name: "Unknown", sortName: "Unknown", slug: "unknown")

        let trackAlbum = album.map {
            Track.TrackAlbum(id: $0.id, name: $0.name, artworkUrl: $0.artworkUrl)
        }

        let albumArtistName = albumArtist?.name ?? artistModel.name
        let albumArtistSortName = albumArtist?.sortName ?? artistModel.sortName

        return Track(
            id: lt.serverId, artistId: lt.artistId, albumArtistId: lt.albumArtistId,
            albumId: lt.albumId, artist: artistModel,
            albumArtistName: albumArtistName, albumArtistSortName: albumArtistSortName,
            album: trackAlbum, name: lt.name,
            disc: lt.disc, number: lt.number, duration: lt.duration,
            mimetype: lt.mimetype, streamUrl: lt.streamUrl, downloadUrl: lt.downloadUrl,
            isDownloaded: lt.isDownloaded
        )
    }
}
