import Foundation
import SwiftData

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

    func markDownloaded(trackId: UUID, relativePath: String, downloadedFileSize: Int64 = 0) {
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        track.isDownloaded = true
        track.localFilePath = relativePath
        track.downloadedFileSize = downloadedFileSize
        persistChanges()
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
        persistChanges()
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
        persistChanges()
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
        persistChanges()
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
        persistChanges()
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
}
