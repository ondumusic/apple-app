import Foundation
import SwiftData

// MARK: - Sync Mutations (called by SyncService)

extension MusicLibrary {

    func bumpRevision() {
        cachedArtistMap = nil
        cachedAlbumMap = nil
        cachedAllTracks = nil
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
                la.artwork = sa.artwork
                la.insertedAt = sa.insertedAt
            } else {
                modelContext.insert(LibraryArtist(
                    serverId: sa.id, name: sa.name, sortName: sa.sortName,
                    slug: sa.slug, albumCount: sa.albumCount, insertedAt: sa.insertedAt,
                                              artwork: sa.artwork))
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
                la.artwork = sa.artwork
                la.isUnknown = sa.isUnknown
                la.trackCount = sa.trackCount
                la.insertedAt = sa.insertedAt
                la.lufs = sa.lufs
            } else {
                modelContext.insert(LibraryAlbum(
                    serverId: sa.id, artistId: sa.artistId, name: sa.name,
                    sortName: sa.sortName, slug: sa.slug,
                    releaseYear: sa.releaseYear, artworkUrl: sa.artworkUrl,
                    artwork: sa.artwork, isUnknown: sa.isUnknown, trackCount: sa.trackCount,
                    insertedAt: sa.insertedAt, lufs: sa.lufs))
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
                lt.lufs = st.lufs
                // The server is authoritative: it has counted plays from every device,
                // where this one has only seen its own.
                lt.playCount = st.playCount
                lt.lastPlayedAt = st.lastPlayedAt
            } else {
                modelContext.insert(LibraryTrack(
                    serverId: st.id, artistId: st.artistId, albumArtistId: st.albumArtistId,
                    albumId: st.albumId, name: st.name, disc: st.disc, number: st.number,
                    duration: st.duration, mimetype: st.mimetype, streamUrl: st.streamUrl,
                    downloadUrl: st.downloadUrl, insertedAt: st.insertedAt, lufs: st.lufs,
                    playCount: st.playCount, lastPlayedAt: st.lastPlayedAt))
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
                lp.isFolder = sp.isFolder
                lp.parentId = sp.parentId
            } else {
                modelContext.insert(LibraryPlaylist(
                    serverId: sp.id, name: sp.name,
                    trackCount: sp.trackCount, insertedAt: sp.insertedAt,
                    isFolder: sp.isFolder, parentId: sp.parentId))
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

    /// Empties the library.
    ///
    /// `includingDownloads` is for logging out, which discards the user's data on
    /// purpose. A re-sync must not pass it: an initial sync clears the tables before
    /// repopulating them, and taking the audio files with it would leave
    /// `reconcileDownloadedFiles()` nothing to put back.
    func clearAll(includingDownloads: Bool = false) {
        if includingDownloads {
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let downloadsDir = appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true)
                try? fm.removeItem(at: downloadsDir)
            }
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
        cachedAllTracks = nil
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

    // MARK: - Local Play Recording (optimistic writes)

    /// Counts a play locally so the UI doesn't wait for the round trip. The next sync
    /// replaces both fields with the server's totals, which include other devices.
    func recordLocalPlay(trackId: UUID, at date: Date) {
        var descriptor = FetchDescriptor<LibraryTrack>(predicate: #Predicate { $0.serverId == trackId })
        descriptor.fetchLimit = 1
        guard let track = fetch(descriptor)?.first else { return }
        track.playCount += 1
        track.lastPlayedAt = date
        persistChanges()
        revision += 1
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
            trackCount: playlist.trackCount, insertedAt: playlist.insertedAt,
            isFolder: playlist.isFolder, parentId: playlist.parentId))
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

    /// Reparents a playlist or folder. `parentId` of nil means root.
    func moveLocalPlaylist(_ id: UUID, to parentId: UUID?) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        guard let lp = fetch(descriptor)?.first else { return }
        lp.parentId = parentId
        persistChanges()
        revision += 1
    }

    /// Recursively collects this playlist and any nested descendants (for folders) into a flat
    /// list of ids. Returned in depth-first pre-order. Server forbids cycles, but the visited
    /// set is a cheap belt-and-suspenders against a malformed local copy.
    func descendantIds(of playlistId: UUID) -> [UUID] {
        var result: [UUID] = []
        var visited: Set<UUID> = []
        var stack: [UUID] = [playlistId]
        while let next = stack.popLast() {
            guard visited.insert(next).inserted else { continue }
            result.append(next)
            let descriptor = FetchDescriptor<LibraryPlaylist>(
                predicate: #Predicate { $0.parentId == next }
            )
            for child in (fetch(descriptor) ?? []) {
                stack.append(child.serverId)
            }
        }
        return result
    }

    func deleteLocalPlaylist(_ id: UUID) {
        // For folders, cascade to all nested descendants locally so the optimistic delete
        // matches what the server will do.
        for descendantId in descendantIds(of: id) {
            deletePlaylistCascade(descendantId)
        }
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
    /// to dependent items and to any child playlists/folders pointing at the temp id.
    /// Called by OutboxService when a queued `create_playlist` finally resolves.
    func remapPlaylistId(from tempId: UUID, to confirmed: Playlist) {
        var descriptor = FetchDescriptor<LibraryPlaylist>(predicate: #Predicate { $0.serverId == tempId })
        descriptor.fetchLimit = 1
        let preservedAutoDownload = fetch(descriptor)?.first?.autoDownload ?? false
        if let playlist = fetch(descriptor)?.first {
            modelContext.delete(playlist)
        }
        modelContext.insert(LibraryPlaylist(
            serverId: confirmed.id, name: confirmed.name,
            trackCount: confirmed.trackCount, insertedAt: confirmed.insertedAt,
            isFolder: confirmed.isFolder, parentId: confirmed.parentId,
            autoDownload: preservedAutoDownload))

        let itemDescriptor = FetchDescriptor<LibraryPlaylistItem>(
            predicate: #Predicate { $0.playlistId == tempId }
        )
        for item in (try? modelContext.fetch(itemDescriptor)) ?? [] {
            item.playlistId = confirmed.id
        }
        // Re-parent any children that referenced the temp folder id.
        let childDescriptor = FetchDescriptor<LibraryPlaylist>(
            predicate: #Predicate { $0.parentId == tempId }
        )
        for child in (try? modelContext.fetch(childDescriptor)) ?? [] {
            child.parentId = confirmed.id
        }
        persistChanges()
        revision += 1
        NotificationCenter.default.post(
            name: .playlistIdRemapped,
            object: nil,
            userInfo: ["temp": tempId, "real": confirmed.id]
        )
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
        case .recordPlays:
            // Nothing in a play refers to a playlist, so nothing in it can need remapping.
            return nil
        case .createPlaylist:
            // The temp playlist id can't change here, but a child folder/playlist may carry
            // the temp parent id — rewrite parentId.
            guard var p = try? decoder.decode(CreatePlaylistPayload.self, from: payload) else { return nil }
            if let parent = p.parentId, let mapped = remap[parent] {
                p.parentId = mapped
                return try? encoder.encode(p)
            }
            return nil
        case .renamePlaylist:
            guard var p = try? decoder.decode(RenamePlaylistPayload.self, from: payload) else { return nil }
            if let mapped = remap[p.playlistId] {
                p.playlistId = mapped
                return try? encoder.encode(p)
            }
            return nil
        case .movePlaylist:
            guard var p = try? decoder.decode(MovePlaylistPayload.self, from: payload) else { return nil }
            var changed = false
            if let mapped = remap[p.playlistId] { p.playlistId = mapped; changed = true }
            if let parent = p.parentId, let mapped = remap[parent] { p.parentId = mapped; changed = true }
            return changed ? (try? encoder.encode(p)) : nil
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

    // MARK: - Outbox compaction

    /// Drops every pending mutation whose target is `playlistId`. Returns true when a pending
    /// `create_playlist` was among them — the playlist never reached the server, so the caller
    /// should skip enqueueing `delete_playlist`. When false, item-ops queued against a server-
    /// known playlist are still dropped (the impending delete will cascade them server-side).
    func compactPendingForDeletedPlaylist(_ playlistId: UUID) -> Bool {
        let mutations = pendingMutations()
        let decoder = JSONDecoder()
        var foundPendingCreate = false
        var deleted = 0

        for mutation in mutations {
            guard let kind = OutboxKind(rawValue: mutation.kind) else { continue }
            let matches: Bool
            switch kind {
            case .recordPlays:
                matches = false
            case .createPlaylist:
                let m = (try? decoder.decode(CreatePlaylistPayload.self, from: mutation.payload))?.tempPlaylistId == playlistId
                if m { foundPendingCreate = true }
                matches = m
            case .renamePlaylist:
                matches = (try? decoder.decode(RenamePlaylistPayload.self, from: mutation.payload))?.playlistId == playlistId
            case .movePlaylist:
                matches = (try? decoder.decode(MovePlaylistPayload.self, from: mutation.payload))?.playlistId == playlistId
            case .deletePlaylist:
                matches = (try? decoder.decode(DeletePlaylistPayload.self, from: mutation.payload))?.playlistId == playlistId
            case .addItems:
                matches = (try? decoder.decode(AddItemsPayload.self, from: mutation.payload))?.playlistId == playlistId
            case .moveItems:
                matches = (try? decoder.decode(MoveItemsPayload.self, from: mutation.payload))?.playlistId == playlistId
            case .removeItems:
                matches = (try? decoder.decode(RemoveItemsPayload.self, from: mutation.payload))?.playlistId == playlistId
            }
            if matches {
                modelContext.delete(mutation)
                deleted += 1
            }
        }

        if deleted > 0 {
            persistChanges()
            #if DEBUG
            print("MusicLibrary.compactPendingForDeletedPlaylist: \(playlistId) — dropped \(deleted) pending mutation(s); pendingCreate=\(foundPendingCreate)")
            #endif
        }
        return foundPendingCreate
    }

    /// Strips each id in `itemIds` from any pending `add_items` and `move_items` payloads.
    /// Mutations emptied by the strip are deleted. Returns the subset of ids found in a
    /// pending `add_items` — the server doesn't know those items yet, so the caller should
    /// skip enqueueing `remove_items` for them.
    func compactPendingForRemovedItems(_ itemIds: Set<UUID>) -> Set<UUID> {
        guard !itemIds.isEmpty else { return [] }
        let mutations = pendingMutations()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var foundInPendingAdds: Set<UUID> = []
        var stripped = 0
        var deletedMutations = 0

        for mutation in mutations {
            guard let kind = OutboxKind(rawValue: mutation.kind) else { continue }
            switch kind {
            case .addItems:
                guard var p = try? decoder.decode(AddItemsPayload.self, from: mutation.payload) else { continue }
                let before = p.items.count
                for entry in p.items where itemIds.contains(entry.tempItemId) {
                    foundInPendingAdds.insert(entry.tempItemId)
                }
                p.items.removeAll { itemIds.contains($0.tempItemId) }
                let removed = before - p.items.count
                if removed > 0 {
                    stripped += removed
                    if p.items.isEmpty {
                        modelContext.delete(mutation)
                        deletedMutations += 1
                    } else if let data = try? encoder.encode(p) {
                        mutation.payload = data
                    }
                }
            case .moveItems:
                guard var p = try? decoder.decode(MoveItemsPayload.self, from: mutation.payload) else { continue }
                let before = p.items.count
                p.items.removeAll { itemIds.contains($0.itemId) }
                let removed = before - p.items.count
                if removed > 0 {
                    stripped += removed
                    if p.items.isEmpty {
                        modelContext.delete(mutation)
                        deletedMutations += 1
                    } else if let data = try? encoder.encode(p) {
                        mutation.payload = data
                    }
                }
            default:
                continue
            }
        }

        if stripped > 0 || deletedMutations > 0 {
            persistChanges()
            #if DEBUG
            print("MusicLibrary.compactPendingForRemovedItems: stripped \(stripped) entr(ies); dropped \(deletedMutations) empty mutation(s); absorbed \(foundInPendingAdds.count) temp id(s)")
            #endif
        }
        return foundInPendingAdds
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
