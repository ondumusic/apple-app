import Foundation
import SwiftData

/// One row of the Downloads list: the album plus what's actually on disk for it.
nonisolated struct DownloadedAlbumEntry: Identifiable, Hashable, Sendable {
    let album: Album
    let trackCount: Int
    let size: Int64

    var id: UUID { album.id }
}

// MARK: - Download Queries & Mutations

extension MusicLibrary {

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
        return tracks.reduce(0) { $0 + $1.downloadedFileSize }
    }

    func downloadedSize(artistId: UUID) -> Int64 {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        let tracks = (try? modelContext.fetch(descriptor)) ?? []
        return tracks.reduce(0) { $0 + $1.downloadedFileSize }
    }

    func localURL(for trackId: UUID) -> URL? {
        _ = downloadChanged
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId && $0.isDownloaded == true })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return nil }
        return track.resolvedFileURL
    }

    nonisolated struct DownloadedSummary {
        var artists: [Artist]
        var totalSize: Int64
        var artistSizes: [UUID: Int64]
    }

    /// Single-query summary of all downloaded content for the Downloads tab.
    func downloadedSummary() -> DownloadedSummary {
        _ = downloadChanged
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        let downloaded = (try? modelContext.fetch(descriptor)) ?? []

        var totalSize: Int64 = 0
        var artistSizes: [UUID: Int64] = [:]
        var artistAlbumIds: [UUID: Set<UUID>] = [:]

        for track in downloaded {
            totalSize += track.downloadedFileSize
            artistSizes[track.albumArtistId, default: 0] += track.downloadedFileSize
            artistAlbumIds[track.albumArtistId, default: []].insert(track.albumId)
        }

        let artistIds = Set(downloaded.map(\.albumArtistId))
        let artistMap = buildArtistMapForIds(artistIds)
        let artists = artistIds.compactMap { id -> Artist? in
            guard let la = artistMap[id] else { return nil }
            return Artist(id: la.serverId, name: la.name, sortName: la.sortName,
                          slug: la.slug, albumCount: artistAlbumIds[id]?.count ?? 0)
        }.sorted { $0.sortName.localizedStandardCompare($1.sortName) == .orderedAscending }

        return DownloadedSummary(artists: artists, totalSize: totalSize, artistSizes: artistSizes)
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
    /// Downloaded albums with their downloaded-track count and on-disk size, gathered in
    /// one pass — the Downloads list needs all three per row and querying each separately
    /// is a fetch per album.
    func downloadedAlbumEntries() -> [DownloadedAlbumEntry] {
        _ = downloadChanged
        _ = revision
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        let downloaded = (try? modelContext.fetch(descriptor)) ?? []
        var counts: [UUID: Int] = [:]
        var sizes: [UUID: Int64] = [:]
        for track in downloaded {
            counts[track.albumId, default: 0] += 1
            sizes[track.albumId, default: 0] += track.downloadedFileSize
        }
        let artistMap = buildArtistMap()
        let albums = (try? modelContext.fetch(FetchDescriptor<LibraryAlbum>())) ?? []
        return albums
            .filter { counts[$0.serverId] != nil }
            .map {
                DownloadedAlbumEntry(album: toAlbum($0, artistMap: artistMap),
                                     trackCount: counts[$0.serverId] ?? 0,
                                     size: sizes[$0.serverId] ?? 0)
            }
            .sorted { a, b in
                let aArtist = a.album.artistSortName ?? a.album.artistName ?? ""
                let bArtist = b.album.artistSortName ?? b.album.artistName ?? ""
                if aArtist != bArtist { return aArtist.localizedStandardCompare(bArtist) == .orderedAscending }
                return a.album.name.localizedStandardCompare(b.album.name) == .orderedAscending
            }
    }

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
                return (a.number ?? Int.max) < (b.number ?? Int.max)
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

    /// Single write point for download-state changes. Patches the cached track list so a
    /// later `allTracks()` doesn't serve pre-download flags, then notifies views.
    func publishDownloadChange(_ changed: [UUID: Bool]) {
        downloadChanged = changed
        if var cached = cachedAllTracks {
            applyDownloadChanges(to: &cached)
            cachedAllTracks = cached
        }
    }

    func markDownloaded(trackId: UUID, relativePath: String, downloadedFileSize: Int64 = 0) {
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        track.isDownloaded = true
        track.localFilePath = relativePath
        track.downloadedFileSize = downloadedFileSize
        persistChanges()
        publishDownloadChange([trackId: true])
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
        persistChanges()
        publishDownloadChange([trackId: false])
    }

    /// Bulk variant of `markUndownloaded(trackId:)` — the single-track version replaces
    /// `downloadChanged` per call, so a loop only propagates the last mutation. This one
    /// builds a combined `downloadChanged` map so views see all the undownloads at once.
    func markTracksUndownloaded(trackIds: Set<UUID>) {
        guard !trackIds.isEmpty else { return }
        let descriptor = FetchDescriptor<LibraryTrack>(
            predicate: #Predicate { trackIds.contains($0.serverId) && $0.isDownloaded == true }
        )
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed: [UUID: Bool] = [:]
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed[track.serverId] = false
        }
        persistChanges()
        publishDownloadChange(changed)
    }

    func markAlbumUndownloaded(albumId: UUID) {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumId == albumId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed: [UUID: Bool] = [:]
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed[track.serverId] = false
        }
        persistChanges()
        publishDownloadChange(changed)
    }

    func markArtistUndownloaded(artistId: UUID) {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.albumArtistId == artistId && $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed: [UUID: Bool] = [:]
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed[track.serverId] = false
        }
        persistChanges()
        publishDownloadChange(changed)
    }

    func markAllUndownloaded() {
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.isDownloaded == true })
        guard let tracks = try? modelContext.fetch(descriptor) else { return }
        var changed: [UUID: Bool] = [:]
        for track in tracks {
            if let url = track.resolvedFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            track.isDownloaded = false
            track.localFilePath = nil
            changed[track.serverId] = false
        }
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let downloadsDir = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            try? fm.removeItem(at: downloadsDir)
        }
        persistChanges()
        publishDownloadChange(changed)
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

    // MARK: - Reconciliation

    /// Re-marks tracks as downloaded by matching the on-disk Downloads/ manifest written
    /// before a SwiftData store reset. Orphaned files (no matching track in the new library)
    /// are deleted. Consumes the manifest on success.
    func reconcileDownloadedFiles() {
        let fm = FileManager.default
        guard let manifestURL = Self.reconciliationManifestURL,
              fm.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([DownloadManifestEntry].self, from: data) else {
            return
        }

        var matched: [UUID: Bool] = [:]
        var reclaimed = 0
        for entry in entries {
            var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == entry.trackId })
            descriptor.fetchLimit = 1
            if let track = try? modelContext.fetch(descriptor).first {
                track.isDownloaded = true
                track.localFilePath = entry.relativePath
                track.downloadedFileSize = entry.fileSize
                matched[entry.trackId] = true
                reclaimed += 1
            } else {
                // Orphan — track no longer in library, remove the file.
                if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let fileURL = appSupport.appendingPathComponent(entry.relativePath)
                    try? fm.removeItem(at: fileURL)
                }
            }
        }

        persistChanges()
        publishDownloadChange(matched)
        #if DEBUG
        print("MusicLibrary: reconciled \(reclaimed)/\(entries.count) downloaded tracks after store reset")
        #endif
        try? fm.removeItem(at: manifestURL)
    }
}
