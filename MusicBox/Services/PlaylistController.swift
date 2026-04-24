import Foundation

/// UI-facing façade for playlist mutations. Every action is synchronous from the caller's
/// perspective: local SwiftData is updated immediately and the server-side replay is queued
/// on `OutboxService`. Errors that matter to the user surface via `OutboxService.lastError`.
@Observable
final class PlaylistController {
    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let outbox: OutboxService

    init(musicLibrary: MusicLibrary, outbox: OutboxService) {
        self.musicLibrary = musicLibrary
        self.outbox = outbox
    }

    // MARK: - Playlist CRUD

    @discardableResult
    func createPlaylist(name: String) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let tempId = UUID()
        let optimistic = Playlist(id: tempId, name: trimmed, trackCount: 0, insertedAt: Date())
        musicLibrary.insertLocalPlaylist(optimistic)
        outbox.enqueueCreatePlaylist(tempId: tempId, name: trimmed)
        return optimistic
    }

    func renamePlaylist(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        musicLibrary.renameLocalPlaylist(id, name: trimmed)
        outbox.enqueueRenamePlaylist(id, name: trimmed)
    }

    func deletePlaylist(_ id: UUID) {
        musicLibrary.deleteLocalPlaylist(id)
        outbox.enqueueDeletePlaylist(id)
    }

    // MARK: - Items

    func addTrack(_ trackId: UUID, to playlistId: UUID) {
        addTracks([trackId], to: playlistId)
    }

    func addTracks(_ trackIds: [UUID], to playlistId: UUID) {
        guard !trackIds.isEmpty else { return }
        var cursor = musicLibrary.lastPlaylistItemPosition(playlistId)
        var entries: [AddItemsPayload.Entry] = []
        entries.reserveCapacity(trackIds.count)
        for trackId in trackIds {
            let position = FractionalIndex.after(cursor)
            cursor = position
            let tempItemId = UUID()
            let tempItem = PlaylistItem(
                id: tempItemId, playlistId: playlistId, trackId: trackId,
                position: position, insertedAt: Date()
            )
            musicLibrary.insertLocalPlaylistItem(tempItem)
            entries.append(.init(tempItemId: tempItemId, trackId: trackId, position: position))
        }
        outbox.enqueueAddItems(playlistId: playlistId, entries: entries)
    }

    func removeItem(_ itemId: UUID, from playlistId: UUID) {
        musicLibrary.deleteLocalPlaylistItem(itemId)
        outbox.enqueueRemoveItems(playlistId: playlistId, itemIds: [itemId])
    }
}
