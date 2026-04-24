import Foundation

/// UI-facing façade for playlist mutations. Every action is synchronous from the caller's
/// perspective: local SwiftData is updated immediately and the server-side replay is queued
/// on `OutboxService`. Errors that matter to the user surface via `OutboxService.lastError`.
@Observable
final class PlaylistController {
    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let outbox: OutboxService
    @ObservationIgnored private let downloadService: DownloadService

    /// Most recently used playlist — powers the "Add to <name>" shortcut in track/album/artist
    /// context menus. Persisted across launches. Set whenever the user adds tracks to a playlist.
    private static let lastUsedKey = "playlists.lastUsedId"
    var lastUsedPlaylistId: UUID? {
        didSet {
            if let id = lastUsedPlaylistId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.lastUsedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastUsedKey)
            }
        }
    }

    init(musicLibrary: MusicLibrary, outbox: OutboxService, downloadService: DownloadService) {
        self.musicLibrary = musicLibrary
        self.outbox = outbox
        self.downloadService = downloadService
        if let raw = UserDefaults.standard.string(forKey: Self.lastUsedKey),
           let id = UUID(uuidString: raw) {
            self.lastUsedPlaylistId = id
        }
    }

    /// Marks a playlist as auto-downloaded and kicks off downloads for any tracks not yet
    /// downloaded. Called from the playlist's Download action in the UI.
    func enableAutoDownload(_ playlistId: UUID) {
        musicLibrary.setPlaylistAutoDownload(id: playlistId, enabled: true)
        let undownloaded = Set(
            musicLibrary.tracksForPlaylist(playlistId)
                .filter { !$0.isDownloaded }
                .map(\.id)
        )
        if !undownloaded.isEmpty {
            downloadService.downloadTracks(ids: undownloaded, library: musicLibrary)
        }
    }

    /// Clears the auto-download flag and removes the playlist's downloaded tracks. Called
    /// from the Remove Download action.
    func disableAutoDownloadAndRemove(_ playlistId: UUID) {
        musicLibrary.setPlaylistAutoDownload(id: playlistId, enabled: false)
        let ids = Set(musicLibrary.tracksForPlaylist(playlistId).map(\.id))
        if !ids.isEmpty {
            musicLibrary.markTracksUndownloaded(trackIds: ids)
        }
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
        if lastUsedPlaylistId == id { lastUsedPlaylistId = nil }
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
        lastUsedPlaylistId = playlistId

        // If the target playlist is flagged for auto-download, queue any just-added tracks
        // that aren't already downloaded. DownloadService dedupes against in-flight downloads.
        if let target = musicLibrary.playlist(playlistId), target.autoDownload {
            let undownloaded = Set(trackIds.filter { !musicLibrary.isDownloaded(trackId: $0) })
            if !undownloaded.isEmpty {
                downloadService.downloadTracks(ids: undownloaded, library: musicLibrary)
            }
        }
    }

    func removeItem(_ itemId: UUID, from playlistId: UUID) {
        musicLibrary.deleteLocalPlaylistItem(itemId)
        outbox.enqueueRemoveItems(playlistId: playlistId, itemIds: [itemId])
    }

    /// Caller computes `newPosition` via `FractionalIndex.between(...)` using the two neighboring
    /// items in the destination order.
    func moveItem(_ itemId: UUID, to newPosition: String, within playlistId: UUID) {
        musicLibrary.moveLocalPlaylistItem(itemId: itemId, newPosition: newPosition)
        outbox.enqueueMoveItems(playlistId: playlistId, entries: [.init(itemId: itemId, position: newPosition)])
    }
}
