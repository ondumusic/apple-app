import Foundation
import SwiftData

@Observable
final class MusicLibrary {
    @ObservationIgnored let modelContainer: ModelContainer

    /// Incremented on content mutations (sync, clear) so views that read it re-evaluate.
    var revision: UInt = 0

    /// Cached maps — invalidated on revision bump to avoid repeated full table scans.
    @ObservationIgnored var cachedArtistMap: [UUID: LibraryArtist]?
    @ObservationIgnored var cachedAlbumMap: [UUID: LibraryAlbum]?

    /// Track IDs whose download state changed. Views observe this to update in-place
    /// without re-querying SwiftData.
    var downloadChanged: Set<UUID> = []

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

    func persistChanges(_ caller: String = #function) {
        do {
            try modelContext.save()
        } catch {
            print("MusicLibrary: save failed in \(caller): \(error)")
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

    func allTracks() -> [Track] {
        _ = revision
        let libTracks = fetch(FetchDescriptor<LibraryTrack>()) ?? []
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
                return (a.number ?? Int.max) < (b.number ?? Int.max)
            }
    }

    // MARK: - Search

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

        let albumDescriptor = FetchDescriptor<LibraryAlbum>(
            predicate: #Predicate {
                $0.trackCount > 0 && (
                    $0.name.localizedStandardContains(query) ||
                    $0.sortName.localizedStandardContains(query)
                )
            }
        )
        let matchedAlbums = fetch(albumDescriptor) ?? []
        let artistIds = Set(matchedAlbums.map(\.artistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let filteredAlbums = matchedAlbums
            .sorted { a, b in
                let aSortName = artistMap[a.artistId]?.sortName ?? ""
                let bSortName = artistMap[b.artistId]?.sortName ?? ""
                if aSortName != bSortName { return aSortName < bSortName }
                let aYear = a.releaseYear ?? 0
                let bYear = b.releaseYear ?? 0
                if aYear != bYear { return aYear > bYear }
                return a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
            }
            .map { toAlbum($0, artistMap: artistMap) }

        let trackDescriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate {
                $0.name.localizedStandardContains(query)
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
        let filteredTracks = matchedTracks
            .map { buildTrack($0, artistMap: trackArtistMap, album: trackAlbumMap[$0.albumId]) }
            .sorted { ($0.artist.sortName, $0.name) < ($1.artist.sortName, $1.name) }

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

        let albumArtistSortName = albumArtist?.sortName ?? artistModel.sortName

        return Track(
            id: lt.serverId, artistId: lt.artistId, albumArtistId: lt.albumArtistId,
            albumId: lt.albumId, artist: artistModel, albumArtistSortName: albumArtistSortName,
            album: trackAlbum, name: lt.name,
            disc: lt.disc, number: lt.number, duration: lt.duration,
            mimetype: lt.mimetype, streamUrl: lt.streamUrl, downloadUrl: lt.downloadUrl,
            isDownloaded: lt.isDownloaded
        )
    }
}
