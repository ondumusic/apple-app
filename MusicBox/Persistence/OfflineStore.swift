import Foundation
import SwiftData

@Observable
final class OfflineStore {
    @ObservationIgnored let modelContainer: ModelContainer

    /// Incremented on every insert/delete so views that read it re-evaluate.
    private(set) var revision: UInt = 0

    init() throws {
        let schema = Schema([
            DownloadedArtist.self, DownloadedAlbum.self, DownloadedTrack.self,
            LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self
        ])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            // Schema changed — delete old store and recreate.
            // Library data is a sync cache and will be re-fetched.
            print("OfflineStore: schema migration failed, resetting database: \(error)")
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupport.appendingPathComponent("default.store")
            for suffix in ["", "-wal", "-shm"] {
                try? fm.removeItem(at: storeURL.appendingPathExtension(suffix.isEmpty ? "" : String(suffix.dropFirst())))
            }
            // Also clear the file with the actual default name SwiftData uses
            if let defaultURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let enumerator = fm.enumerator(at: defaultURL, includingPropertiesForKeys: nil)
                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.lastPathComponent.hasSuffix(".store") ||
                       fileURL.lastPathComponent.hasSuffix(".store-wal") ||
                       fileURL.lastPathComponent.hasSuffix(".store-shm") {
                        try? fm.removeItem(at: fileURL)
                    }
                }
            }
            // Clear sync cursor so a full re-sync happens
            SyncService.clearSyncState()
            modelContainer = try ModelContainer(for: schema)
        }
    }

    var modelContext: ModelContext { modelContainer.mainContext }

    func isDownloaded(trackId: UUID) -> Bool {
        _ = revision
        let descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == trackId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func isAlbumDownloaded(albumId: UUID) -> Bool {
        _ = revision
        let descriptor = FetchDescriptor<DownloadedAlbum>(predicate: #Predicate { $0.id == albumId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func isArtistDownloaded(artistId: UUID) -> Bool {
        _ = revision
        let descriptor = FetchDescriptor<DownloadedArtist>(predicate: #Predicate { $0.id == artistId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func downloadedTrackCount(albumId: UUID) -> Int {
        _ = revision
        let descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.albumId == albumId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func localURL(for trackId: UUID) -> URL? {
        _ = revision
        var descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else {
            print("OfflineStore: no downloaded track found for \(trackId)")
            return nil
        }
        let url = track.resolvedFileURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        print("OfflineStore: localURL for \(track.name) → \(url.lastPathComponent), exists=\(exists), trackArtistId=\(track.artistId), albumArtistId=\(track.album?.artistId.uuidString ?? "nil")")
        if !exists {
            print("OfflineStore: full path: \(url.path)")
        }
        return url
    }

    func availableTracks(_ tracks: [Track], isOnline: Bool) -> [Track] {
        if isOnline { return tracks }
        return tracks.filter { isDownloaded(trackId: $0.id) }
    }

    func availableItems(_ items: [QueueItem], isOnline: Bool) -> [QueueItem] {
        if isOnline { return items }
        return items.filter { isDownloaded(trackId: $0.track.id) }
    }

    func downloadedArtists() -> [DownloadedArtist] {
        _ = revision
        let descriptor = FetchDescriptor<DownloadedArtist>(sortBy: [SortDescriptor(\.name)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func ensureArtist(from artist: Artist) -> DownloadedArtist {
        let artistId = artist.id
        var descriptor = FetchDescriptor<DownloadedArtist>(predicate: #Predicate { $0.id == artistId })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first { return existing }
        let new = DownloadedArtist(id: artist.id, name: artist.name)
        modelContext.insert(new)
        return new
    }

    func ensureAlbum(from album: Album, artist: DownloadedArtist) -> DownloadedAlbum {
        let albumId = album.id
        var descriptor = FetchDescriptor<DownloadedAlbum>(predicate: #Predicate { $0.id == albumId })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first { return existing }
        let new = DownloadedAlbum(
            id: album.id, artistId: album.artistId, name: album.name,
            releaseYear: album.releaseYear, artworkUrl: album.artworkUrl
        )
        new.artist = artist
        modelContext.insert(new)
        return new
    }

    func insertTrack(_ track: Track, localFileURL: URL, album: DownloadedAlbum) {
        let downloaded = DownloadedTrack(from: track, localFileURL: localFileURL)
        downloaded.album = album
        modelContext.insert(downloaded)
        try? modelContext.save()
        revision += 1
    }

    func deleteTrack(trackId: UUID) {
        var descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        try? FileManager.default.removeItem(at: track.resolvedFileURL)
        let album = track.album
        modelContext.delete(track)
        if let album, album.tracks.count <= 1 {
            let artist = album.artist
            modelContext.delete(album)
            if let artist, artist.albums.count <= 1 {
                modelContext.delete(artist)
            }
        }
        try? modelContext.save()
        revision += 1
    }

    func deleteAlbum(albumId: UUID) {
        let id = albumId
        var descriptor = FetchDescriptor<DownloadedAlbum>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let album = try? modelContext.fetch(descriptor).first else { return }
        for track in album.tracks {
            try? FileManager.default.removeItem(at: track.resolvedFileURL)
        }
        let artist = album.artist
        modelContext.delete(album)
        if let artist, artist.albums.count <= 1 {
            modelContext.delete(artist)
        }
        try? modelContext.save()
        revision += 1
    }

    func deleteArtist(artistId: UUID) {
        let id = artistId
        var descriptor = FetchDescriptor<DownloadedArtist>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let artist = try? modelContext.fetch(descriptor).first else { return }
        for album in artist.albums {
            for track in album.tracks {
                try? FileManager.default.removeItem(at: track.resolvedFileURL)
            }
        }
        modelContext.delete(artist)
        try? modelContext.save()
        revision += 1
    }

    func deleteAll() {
        let artists = (try? modelContext.fetch(FetchDescriptor<DownloadedArtist>())) ?? []
        for artist in artists {
            for album in artist.albums {
                for track in album.tracks {
                    try? FileManager.default.removeItem(at: track.resolvedFileURL)
                }
            }
            modelContext.delete(artist)
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
}
