import Foundation

/// Durable replay queue for playlist mutations. UI writes to the local store synchronously
/// and enqueues the corresponding op here; this service drains the queue whenever a network
/// path is available.
///
/// Temp UUIDs minted by the UI for create_playlist / add_items are swapped for server-assigned
/// UUIDs on successful replay, both in the local SwiftData store and in downstream payloads
/// still waiting in the queue.
@Observable
final class OutboxService {
    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let api: APIService

    /// Number of mutations still waiting to replay — observed by UI indicators.
    var pendingCount: Int = 0
    /// One-shot surface for the most recent hard failure that was discarded (e.g. 404 on delete).
    /// UIs observe this to show an alert and clear by setting back to nil.
    var lastError: String?

    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    init(musicLibrary: MusicLibrary, api: APIService) {
        self.musicLibrary = musicLibrary
        self.api = api
        refreshPendingCount()
    }

    deinit {
        retryTask?.cancel()
    }

    // MARK: - Enqueue

    func enqueueCreatePlaylist(tempId: UUID, name: String) {
        enqueue(.createPlaylist, payload: CreatePlaylistPayload(tempPlaylistId: tempId, name: name))
    }

    func enqueueRenamePlaylist(_ id: UUID, name: String) {
        enqueue(.renamePlaylist, payload: RenamePlaylistPayload(playlistId: id, name: name))
    }

    func enqueueDeletePlaylist(_ id: UUID) {
        enqueue(.deletePlaylist, payload: DeletePlaylistPayload(playlistId: id))
    }

    func enqueueAddItems(playlistId: UUID, entries: [AddItemsPayload.Entry]) {
        guard !entries.isEmpty else { return }
        enqueue(.addItems, payload: AddItemsPayload(playlistId: playlistId, items: entries))
    }

    func enqueueRemoveItems(playlistId: UUID, itemIds: [UUID]) {
        guard !itemIds.isEmpty else { return }
        enqueue(.removeItems, payload: RemoveItemsPayload(playlistId: playlistId, itemIds: itemIds))
    }

    private func enqueue<P: Encodable>(_ kind: OutboxKind, payload: P) {
        guard let data = try? JSONEncoder().encode(payload) else {
            #if DEBUG
            print("OutboxService: failed to encode \(kind.rawValue) payload")
            #endif
            return
        }
        let mutation = PendingMutation(kind: kind.rawValue, payload: data)
        musicLibrary.enqueuePendingMutation(mutation)
        refreshPendingCount()
        Task { await flush() }
    }

    // MARK: - Flush

    /// Drains the queue in order. Stops at the first retryable failure (no immediate re-attempt —
    /// the next trigger picks it up). Idempotent; concurrent calls share one flush.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        retryTask?.cancel()
        retryTask = nil
        defer { isFlushing = false }

        while let next = musicLibrary.pendingMutations().first {
            let outcome = await process(next)
            switch outcome {
            case .success:
                musicLibrary.deletePendingMutation(next)
            case .discard(let reason):
                lastError = reason
                musicLibrary.deletePendingMutation(next)
            case .retry(let reason):
                next.attemptCount += 1
                next.lastError = reason
                next.lastAttemptAt = Date()
                musicLibrary.persistChanges()
                refreshPendingCount()
                scheduleRetry()
                return
            }
            refreshPendingCount()
        }
    }

    private enum Outcome {
        case success
        case retry(String)
        case discard(String)
    }

    /// Retry policy, in one place:
    /// - 422 is the only status we treat as permanently bad (invalid input the server will never accept).
    /// - 404 on delete is treated as success (already gone).
    /// - Everything else retries indefinitely. Missing endpoints (pre-upgrade servers), 5xx outages, and
    ///   transient network issues all resolve themselves once the server is healthy again.
    /// - We never roll back local state on discard — the next sync reconciles authoritatively.
    private func process(_ mutation: PendingMutation) async -> Outcome {
        guard let kind = OutboxKind(rawValue: mutation.kind) else {
            return .discard("Unknown mutation kind: \(mutation.kind)")
        }
        let decoder = JSONDecoder()

        switch kind {
        case .createPlaylist:
            guard let p = try? decoder.decode(CreatePlaylistPayload.self, from: mutation.payload) else {
                return .discard("Malformed create_playlist payload")
            }
            do {
                let server = try await api.createPlaylist(name: p.name)
                musicLibrary.remapPlaylistId(from: p.tempPlaylistId, to: server)
                musicLibrary.remapQueuedPlaylistId(from: p.tempPlaylistId, to: server.id)
                return .success
            } catch APIError.httpError(422) {
                return .discard("Couldn't create playlist “\(p.name)” — the name is invalid.")
            } catch {
                return .retry(error.localizedDescription)
            }

        case .renamePlaylist:
            guard let p = try? decoder.decode(RenamePlaylistPayload.self, from: mutation.payload) else {
                return .discard("Malformed rename_playlist payload")
            }
            do {
                _ = try await api.renamePlaylist(p.playlistId, name: p.name)
                return .success
            } catch APIError.httpError(422) {
                return .discard("Couldn't rename playlist — the name is invalid.")
            } catch {
                return .retry(error.localizedDescription)
            }

        case .deletePlaylist:
            guard let p = try? decoder.decode(DeletePlaylistPayload.self, from: mutation.payload) else {
                return .discard("Malformed delete_playlist payload")
            }
            do {
                try await api.deletePlaylist(p.playlistId)
                return .success
            } catch APIError.httpError(404) {
                return .success  // already gone, local delete was correct
            } catch {
                return .retry(error.localizedDescription)
            }

        case .addItems:
            guard let p = try? decoder.decode(AddItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed add_items payload")
            }
            do {
                let adds = p.items.map { APIService.PositionedTrackBody(trackId: $0.trackId, position: $0.position) }
                let response = try await api.updatePlaylistItems(p.playlistId, add: adds)
                // Pair temp item IDs to server items by position (unique in this batch).
                let addedByPosition = Dictionary(uniqueKeysWithValues: response.added.map { ($0.position, $0) })
                for entry in p.items {
                    if let confirmed = addedByPosition[entry.position] {
                        musicLibrary.swapLocalPlaylistItemId(tempId: entry.tempItemId, confirmed: confirmed)
                    }
                }
                return .success
            } catch APIError.httpError(422) {
                return .discard("Some tracks couldn't be added — they were rejected by the server.")
            } catch {
                return .retry(error.localizedDescription)
            }

        case .removeItems:
            guard let p = try? decoder.decode(RemoveItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed remove_items payload")
            }
            do {
                _ = try await api.updatePlaylistItems(p.playlistId, remove: p.itemIds)
                return .success
            } catch APIError.httpError(404) {
                return .success  // playlist/items already gone, local removal was correct
            } catch {
                return .retry(error.localizedDescription)
            }
        }
    }

    // MARK: - Retry scheduling

    /// Schedules one delayed retry. The next foreground / connectivity / enqueue trigger will
    /// cancel this and flush promptly.
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func refreshPendingCount() {
        pendingCount = musicLibrary.pendingMutations().count
    }
}
