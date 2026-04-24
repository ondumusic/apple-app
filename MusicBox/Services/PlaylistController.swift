import Foundation

/// Bridges playlist UI actions to the API + local SwiftData store.
///
/// Policy:
/// - Create/rename/delete playlist: server-first. A brief spinner in the UI is fine; these are
///   single calls and the list view re-queries after success.
/// - Add/remove items: optimistic. Items appear/disappear instantly; server call reconciles the
///   real item ID (for adds) or reverts on failure.
@Observable
final class PlaylistController {
    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let musicLibrary: MusicLibrary

    /// One-shot error surface for the most recent failed mutation. UIs observe this to show
    /// a transient banner/alert and clear by setting back to nil.
    var lastError: String?

    init(api: APIService, musicLibrary: MusicLibrary) {
        self.api = api
        self.musicLibrary = musicLibrary
    }

    // MARK: - Playlist CRUD

    @discardableResult
    func createPlaylist(name: String) async -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let playlist = try await api.createPlaylist(name: trimmed)
            musicLibrary.insertLocalPlaylist(playlist)
            return playlist
        } catch {
            lastError = "Couldn't create playlist: \(error.localizedDescription)"
            return nil
        }
    }

    func renamePlaylist(_ id: UUID, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let playlist = try await api.renamePlaylist(id, name: trimmed)
            musicLibrary.renameLocalPlaylist(id, name: playlist.name)
        } catch {
            lastError = "Couldn't rename playlist: \(error.localizedDescription)"
        }
    }

    func deletePlaylist(_ id: UUID) async {
        do {
            try await api.deletePlaylist(id)
            musicLibrary.deleteLocalPlaylist(id)
        } catch {
            lastError = "Couldn't delete playlist: \(error.localizedDescription)"
        }
    }

    // MARK: - Items

    /// Appends a track to the playlist. Optimistically inserts a local item with a temp UUID,
    /// then replaces it with the server-issued item on success (or removes it on failure).
    func addTrack(_ trackId: UUID, to playlistId: UUID) async {
        let lastPos = musicLibrary.lastPlaylistItemPosition(playlistId)
        let position = FractionalIndex.after(lastPos)
        let tempId = UUID()
        let tempItem = PlaylistItem(
            id: tempId, playlistId: playlistId, trackId: trackId,
            position: position, insertedAt: Date()
        )
        musicLibrary.insertLocalPlaylistItem(tempItem)

        do {
            let response = try await api.updatePlaylistItems(
                playlistId,
                add: [.init(trackId: trackId, position: position)]
            )
            if let added = response.added.first {
                musicLibrary.swapLocalPlaylistItemId(tempId: tempId, confirmed: added)
            }
        } catch {
            musicLibrary.deleteLocalPlaylistItem(tempId)
            lastError = "Couldn't add to playlist: \(error.localizedDescription)"
        }
    }

    /// Append multiple tracks in one batched call — used by "Save Queue as Playlist".
    @discardableResult
    func addTracks(_ trackIds: [UUID], to playlistId: UUID) async -> Bool {
        guard !trackIds.isEmpty else { return true }
        var cursor = musicLibrary.lastPlaylistItemPosition(playlistId)
        var tempIds: [(tempId: UUID, trackId: UUID, position: String)] = []
        tempIds.reserveCapacity(trackIds.count)
        for trackId in trackIds {
            let position = FractionalIndex.after(cursor)
            cursor = position
            let tempId = UUID()
            let tempItem = PlaylistItem(
                id: tempId, playlistId: playlistId, trackId: trackId,
                position: position, insertedAt: Date()
            )
            musicLibrary.insertLocalPlaylistItem(tempItem)
            tempIds.append((tempId, trackId, position))
        }

        do {
            let response = try await api.updatePlaylistItems(
                playlistId,
                add: tempIds.map { .init(trackId: $0.trackId, position: $0.position) }
            )
            // Pair up server-added items to their temp inserts by position (unique within this batch).
            let addedByPosition = Dictionary(uniqueKeysWithValues: response.added.map { ($0.position, $0) })
            for temp in tempIds {
                if let confirmed = addedByPosition[temp.position] {
                    musicLibrary.swapLocalPlaylistItemId(tempId: temp.tempId, confirmed: confirmed)
                }
            }
            return true
        } catch {
            for temp in tempIds {
                musicLibrary.deleteLocalPlaylistItem(temp.tempId)
            }
            lastError = "Couldn't add tracks to playlist: \(error.localizedDescription)"
            return false
        }
    }

    /// Removes an item. Optimistically deletes locally and restores on server failure.
    func removeItem(_ itemId: UUID, from playlistId: UUID) async {
        let items = musicLibrary.playlistItems(playlistId)
        guard let item = items.first(where: { $0.id == itemId }) else { return }
        musicLibrary.deleteLocalPlaylistItem(itemId)

        do {
            _ = try await api.updatePlaylistItems(playlistId, remove: [itemId])
        } catch {
            // Restore the local item so the UI stays honest.
            musicLibrary.insertLocalPlaylistItem(item)
            lastError = "Couldn't remove from playlist: \(error.localizedDescription)"
        }
    }
}
