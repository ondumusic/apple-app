import Foundation
import SwiftData

// MARK: - Sync Mutations (called by SyncService)

extension MusicLibrary {

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
        persistChanges()
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
        persistChanges()
        return inserted
    }

    /// Returns the server IDs of newly inserted tracks.
    @discardableResult
    func upsertTracks(_ syncTracks: [SyncTrack]) -> Set<UUID> {
        guard !syncTracks.isEmpty else { return [] }
        let ids = syncTracks.map(\.id)
        let descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { ids.contains($0.serverId) })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        var inserted = Set<UUID>()
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
                inserted.insert(st.id)
            }
        }
        persistChanges()
        return inserted
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
        persistChanges()
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
        persistChanges()
        cachedArtistMap = nil
        cachedAlbumMap = nil
        revision += 1
    }

    // MARK: - Cascade Deletes

    func deleteArtistCascade(_ artistId: UUID) {
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

    func deleteAlbumCascade(_ albumId: UUID) {
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
