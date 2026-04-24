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
            } else {
                modelContext.insert(LibraryTrack(
                    serverId: st.id, artistId: st.artistId, albumArtistId: st.albumArtistId,
                    albumId: st.albumId, name: st.name, disc: st.disc, number: st.number,
                    duration: st.duration, mimetype: st.mimetype, streamUrl: st.streamUrl,
                    downloadUrl: st.downloadUrl, insertedAt: st.insertedAt))
                inserted.insert(st.id)
            }
        }
        persistChanges()
        return inserted
    }

    @discardableResult
    func upsertPlaylists(_ syncPlaylists: [SyncPlaylist]) -> Set<UUID> {
        guard !syncPlaylists.isEmpty else { return [] }
        let ids = syncPlaylists.map(\.id)
        let descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { ids.contains($0.serverId) })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        var inserted = Set<UUID>()
        for sp in syncPlaylists {
            if let lp = map[sp.id] {
                lp.name = sp.name
                lp.trackCount = sp.trackCount
                lp.insertedAt = sp.insertedAt
            } else {
                modelContext.insert(LibraryPlaylist(
                    serverId: sp.id, name: sp.name,
                    trackCount: sp.trackCount, insertedAt: sp.insertedAt))
                inserted.insert(sp.id)
            }
        }
        persistChanges()
        return inserted
    }

    @discardableResult
    func upsertPlaylistItems(_ syncItems: [SyncPlaylistItem]) -> Set<UUID> {
        guard !syncItems.isEmpty else { return [] }
        let ids = syncItems.map(\.id)
        let descriptor = FetchDescriptor<LibraryPlaylistItem>(predicate: #Predicate { ids.contains($0.serverId) })
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        var inserted = Set<UUID>()
        for si in syncItems {
            if let li = map[si.id] {
                li.playlistId = si.playlistId
                li.trackId = si.trackId
                li.position = si.position
                li.insertedAt = si.insertedAt
            } else {
                modelContext.insert(LibraryPlaylistItem(
                    serverId: si.id, playlistId: si.playlistId, trackId: si.trackId,
                    position: si.position, insertedAt: si.insertedAt))
                inserted.insert(si.id)
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
            case "playlist":
                deletePlaylistCascade(deletion.entityId)
            case "playlistItem":
                let id = deletion.entityId
                var descriptor = FetchDescriptor<LibraryPlaylistItem>(predicate: #Predicate { $0.serverId == id })
                descriptor.fetchLimit = 1
                if let item = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(item)
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
        try? modelContext.delete(model: LibraryPlaylistItem.self)
        try? modelContext.delete(model: LibraryPlaylist.self)
        try? modelContext.delete(model: PendingMutation.self)
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

    // MARK: - Local Playlist Mutations (optimistic writes)

    /// Returns the last position string currently in the playlist, for computing an append position.
    func lastPlaylistItemPosition(_ playlistId: UUID) -> String? {
        var descriptor = FetchDescriptor<LibraryPlaylistItem>(
            predicate: #Predicate { $0.playlistId == playlistId },
            sortBy: [SortDescriptor(\.position, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor)?.first?.position
    }

    func insertLocalPlaylist(_ playlist: Playlist) {
        modelContext.insert(LibraryPlaylist(
            serverId: playlist.id, name: playlist.name,
            trackCount: playlist.trackCount, insertedAt: playlist.insertedAt))
        persistChanges()
        revision += 1
    }

    func renameLocalPlaylist(_ id: UUID, name: String) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let lp = fetch(descriptor)?.first else { return }
        lp.name = name
        persistChanges()
        revision += 1
    }

    func deleteLocalPlaylist(_ id: UUID) {
        deletePlaylistCascade(id)
        persistChanges()
        revision += 1
    }

    /// Inserts a local PlaylistItem, also bumping the parent playlist's track count.
    func insertLocalPlaylistItem(_ item: PlaylistItem) {
        modelContext.insert(LibraryPlaylistItem(
            serverId: item.id, playlistId: item.playlistId, trackId: item.trackId,
            position: item.position, insertedAt: item.insertedAt))
        adjustPlaylistTrackCount(item.playlistId, delta: 1)
        persistChanges()
        revision += 1
    }

    func deleteLocalPlaylistItem(_ id: UUID) {
        var descriptor = FetchDescriptor<LibraryPlaylistItem>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let item = fetch(descriptor)?.first else { return }
        let playlistId = item.playlistId
        modelContext.delete(item)
        adjustPlaylistTrackCount(playlistId, delta: -1)
        persistChanges()
        revision += 1
    }

    /// Replaces a temp item ID with the real server-assigned ID (used after an optimistic add).
    /// Also rewrites any queued move/remove payloads still targeting the temp ID.
    func swapLocalPlaylistItemId(tempId: UUID, confirmed: PlaylistItem) {
        var descriptor = FetchDescriptor<LibraryPlaylistItem>(predicate: #Predicate { $0.serverId == tempId })
        descriptor.fetchLimit = 1
        if let item = fetch(descriptor)?.first {
            modelContext.delete(item)
        }
        modelContext.insert(LibraryPlaylistItem(
            serverId: confirmed.id, playlistId: confirmed.playlistId, trackId: confirmed.trackId,
            position: confirmed.position, insertedAt: confirmed.insertedAt))
        persistChanges()
        remapQueuedPlaylistItemId(from: tempId, to: confirmed.id)
        revision += 1
    }

    /// Rewrites queued move/remove payloads so any reference to `tempId` becomes `realId`.
    func remapQueuedPlaylistItemId(from tempId: UUID, to realId: UUID) {
        let mutations = pendingMutations()
        var rewrittenCount = 0
        for mutation in mutations {
            guard let kind = OutboxKind(rawValue: mutation.kind) else { continue }
            guard let rewritten = rewrittenItemIdPayload(kind: kind, payload: mutation.payload, from: tempId, to: realId) else { continue }
            mutation.payload = rewritten
            rewrittenCount += 1
        }
        persistChanges()
        #if DEBUG
        if rewrittenCount > 0 {
            print("MusicLibrary.remapQueuedPlaylistItemId: temp=\(tempId) → real=\(realId), rewritten=\(rewrittenCount)")
        }
        #endif
    }

    /// Updates a local item's position — called by the optimistic move path.
    func moveLocalPlaylistItem(itemId: UUID, newPosition: String) {
        var descriptor = FetchDescriptor<LibraryPlaylistItem>(predicate: #Predicate { $0.serverId == itemId })
        descriptor.fetchLimit = 1
        guard let item = fetch(descriptor)?.first else { return }
        item.position = newPosition
        persistChanges()
        revision += 1
    }

    private func rewrittenItemIdPayload(kind: OutboxKind, payload: Data, from tempId: UUID, to realId: UUID) -> Data? {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        switch kind {
        case .moveItems:
            guard var p = try? decoder.decode(MoveItemsPayload.self, from: payload) else { return nil }
            var changed = false
            p.items = p.items.map { entry in
                if entry.itemId == tempId {
                    changed = true
                    return MoveItemsPayload.Entry(itemId: realId, position: entry.position)
                }
                return entry
            }
            return changed ? (try? encoder.encode(p)) : nil
        case .removeItems:
            guard var p = try? decoder.decode(RemoveItemsPayload.self, from: payload) else { return nil }
            var changed = false
            p.itemIds = p.itemIds.map { id in
                if id == tempId { changed = true; return realId }
                return id
            }
            return changed ? (try? encoder.encode(p)) : nil
        default:
            return nil
        }
    }

    private func adjustPlaylistTrackCount(_ playlistId: UUID, delta: Int) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == playlistId })
        descriptor.fetchLimit = 1
        if let playlist = fetch(descriptor)?.first {
            playlist.trackCount = max(0, playlist.trackCount + delta)
        }
    }

    /// Rewrites a local playlist's identity from a temp UUID to the server-confirmed UUID, cascading
    /// to dependent items. Called by OutboxService when a queued `create_playlist` finally resolves.
    func remapPlaylistId(from tempId: UUID, to confirmed: Playlist) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == tempId })
        descriptor.fetchLimit = 1
        if let playlist = fetch(descriptor)?.first {
            modelContext.delete(playlist)
        }
        modelContext.insert(LibraryPlaylist(
            serverId: confirmed.id, name: confirmed.name,
            trackCount: confirmed.trackCount, insertedAt: confirmed.insertedAt))

        let itemDescriptor = FetchDescriptor<LibraryPlaylistItem>(
            predicate: #Predicate { $0.playlistId == tempId }
        )
        for item in (try? modelContext.fetch(itemDescriptor)) ?? [] {
            item.playlistId = confirmed.id
        }
        persistChanges()
        revision += 1
    }

    // MARK: - Pending mutations (outbox)

    func pendingMutations() -> [PendingMutation] {
        let descriptor = FetchDescriptor<PendingMutation>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return fetch(descriptor) ?? []
    }

    func enqueuePendingMutation(_ mutation: PendingMutation) {
        modelContext.insert(mutation)
        persistChanges()
    }

    func deletePendingMutation(_ mutation: PendingMutation) {
        modelContext.delete(mutation)
        persistChanges()
    }

    /// Rewrites payloads of queued mutations so any reference to `tempId` becomes `realId`.
    /// Called after a successful `create_playlist` so dependent ops fire against the real playlist.
    func remapQueuedPlaylistId(from tempId: UUID, to realId: UUID) {
        let mutations = pendingMutations()
        var rewrittenCount = 0
        for mutation in mutations {
            guard let kind = OutboxKind(rawValue: mutation.kind) else { continue }
            guard let rewritten = rewrittenPayload(kind: kind, payload: mutation.payload, remap: [tempId: realId]) else { continue }
            mutation.payload = rewritten
            rewrittenCount += 1
        }
        persistChanges()
        #if DEBUG
        print("MusicLibrary.remapQueuedPlaylistId: temp=\(tempId) → real=\(realId), scanned=\(mutations.count), rewritten=\(rewrittenCount)")
        #endif
    }

    private func rewrittenPayload(kind: OutboxKind, payload: Data, remap: [UUID: UUID]) -> Data? {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        switch kind {
        case .createPlaylist:
            // Temp playlist IDs are already embedded; nothing to rewrite.
            return nil
        case .renamePlaylist:
            guard var p = try? decoder.decode(RenamePlaylistPayload.self, from: payload) else { return nil }
            if let mapped = remap[p.playlistId] {
                p.playlistId = mapped
                return try? encoder.encode(p)
            }
            return nil
        case .deletePlaylist:
            guard var p = try? decoder.decode(DeletePlaylistPayload.self, from: payload) else { return nil }
            if let mapped = remap[p.playlistId] {
                p.playlistId = mapped
                return try? encoder.encode(p)
            }
            return nil
        case .addItems:
            guard var p = try? decoder.decode(AddItemsPayload.self, from: payload) else { return nil }
            if let mapped = remap[p.playlistId] {
                p.playlistId = mapped
                return try? encoder.encode(p)
            }
            return nil
        case .moveItems:
            guard var p = try? decoder.decode(MoveItemsPayload.self, from: payload) else { return nil }
            if let mapped = remap[p.playlistId] {
                p.playlistId = mapped
                return try? encoder.encode(p)
            }
            return nil
        case .removeItems:
            guard var p = try? decoder.decode(RemoveItemsPayload.self, from: payload) else { return nil }
            if let mapped = remap[p.playlistId] {
                p.playlistId = mapped
                return try? encoder.encode(p)
            }
            return nil
        }
    }

    func deletePlaylistCascade(_ playlistId: UUID) {
        let itemDescriptor = FetchDescriptor<LibraryPlaylistItem>(predicate: #Predicate { $0.playlistId == playlistId })
        for item in (try? modelContext.fetch(itemDescriptor)) ?? [] {
            modelContext.delete(item)
        }
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == playlistId })
        descriptor.fetchLimit = 1
        if let playlist = try? modelContext.fetch(descriptor).first {
            modelContext.delete(playlist)
        }
    }
}
