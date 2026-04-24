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

    /// After this many transient failures in a row, escalate to a discard so one bad mutation
    /// can't permanently block the queue. Real outages (server down for a day) are well under this.
    @ObservationIgnored private let maxRetryAttempts = 20

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

    func enqueueMoveItems(playlistId: UUID, entries: [MoveItemsPayload.Entry]) {
        guard !entries.isEmpty else { return }
        enqueue(.moveItems, payload: MoveItemsPayload(playlistId: playlistId, items: entries))
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
        guard !isFlushing else {
            #if DEBUG
            print("OutboxService: flush skipped — already in progress")
            #endif
            return
        }
        isFlushing = true
        retryTask?.cancel()
        retryTask = nil
        defer { isFlushing = false }

        let initialCount = musicLibrary.pendingMutations().count
        #if DEBUG
        if initialCount > 0 {
            print("OutboxService: flushing \(initialCount) mutation(s)")
        }
        #endif

        while let next = musicLibrary.pendingMutations().first {
            let outcome = await process(next)
            switch outcome {
            case .success:
                #if DEBUG
                print("OutboxService: \(next.kind) succeeded")
                #endif
                musicLibrary.deletePendingMutation(next)
            case .discard(let reason):
                #if DEBUG
                print("OutboxService: \(next.kind) discarded — \(reason)")
                #endif
                lastError = reason
                musicLibrary.deletePendingMutation(next)
            case .retry(let reason):
                next.attemptCount += 1
                next.lastError = reason
                next.lastAttemptAt = Date()
                if next.attemptCount >= maxRetryAttempts {
                    #if DEBUG
                    print("OutboxService: \(next.kind) giving up after \(next.attemptCount) attempts — \(reason)")
                    #endif
                    lastError = "A playlist change couldn't sync: \(reason)"
                    musicLibrary.deletePendingMutation(next)
                    refreshPendingCount()
                    continue  // try the next mutation
                }
                #if DEBUG
                print("OutboxService: \(next.kind) retry (attempt \(next.attemptCount)) — \(reason)")
                #endif
                musicLibrary.persistChanges()
                refreshPendingCount()
                scheduleRetry()
                return

            case .retryNoPenalty(let reason):
                next.lastError = reason
                next.lastAttemptAt = Date()
                #if DEBUG
                print("OutboxService: \(next.kind) paused (no-penalty) — \(reason)")
                #endif
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
        /// Retry later, and count this attempt toward the cap.
        case retry(String)
        /// Retry later, but don't count toward the cap — used for transient conditions that will
        /// resolve themselves externally (offline, expired auth).
        case retryNoPenalty(String)
        case discard(String)
    }

    /// Retry policy, in one place:
    /// - 422 is the only status we treat as permanently bad (invalid input the server will never accept).
    /// - 404 on delete is treated as success (already gone).
    /// - If the target playlist no longer exists locally, the mutation is orphaned — skip as success
    ///   rather than retry against an id the server will never recognize.
    /// - Everything else retries up to `maxRetryAttempts`, then escalates to discard + alert.
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
            // The local playlist this mutation was meant to materialize is already gone (user deleted
            // it locally before we synced) — don't bother creating it on the server.
            if musicLibrary.playlist(p.tempPlaylistId) == nil {
                #if DEBUG
                print("OutboxService: create_playlist skipped — local playlist \(p.tempPlaylistId) no longer exists")
                #endif
                return .success
            }
            do {
                let server = try await api.createPlaylist(name: p.name)
                #if DEBUG
                print("OutboxService: create_playlist OK — temp=\(p.tempPlaylistId) → real=\(server.id)")
                #endif
                musicLibrary.remapPlaylistId(from: p.tempPlaylistId, to: server)
                musicLibrary.remapQueuedPlaylistId(from: p.tempPlaylistId, to: server.id)
                return .success
            } catch APIError.httpError(422) {
                return .discard("Couldn't create playlist “\(p.name)” — the name is invalid.")
            } catch {
                return classify(error)
            }

        case .renamePlaylist:
            guard let p = try? decoder.decode(RenamePlaylistPayload.self, from: mutation.payload) else {
                return .discard("Malformed rename_playlist payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil {
                #if DEBUG
                print("OutboxService: rename_playlist skipped — local playlist \(p.playlistId) no longer exists")
                #endif
                return .success
            }
            do {
                _ = try await api.renamePlaylist(p.playlistId, name: p.name)
                return .success
            } catch APIError.httpError(422) {
                return .discard("Couldn't rename playlist — the name is invalid.")
            } catch {
                return classify(error)
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
                return classify(error)
            }

        case .addItems:
            guard let p = try? decoder.decode(AddItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed add_items payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil {
                #if DEBUG
                print("OutboxService: add_items skipped — local playlist \(p.playlistId) no longer exists")
                #endif
                return .success
            }
            #if DEBUG
            print("OutboxService: add_items firing — playlistId=\(p.playlistId), items=\(p.items.count)")
            #endif
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
            } catch APIError.httpError(400) {
                // PATCH /playlists/{id}/items uses 400 for its discriminated error union
                // (too_many_operations, unknown_tracks, add_move_conflict, etc.). The
                // specific reason was already printed by APIService.perform; surface a
                // generic message and discard so the queue doesn't loop.
                return .discard("Some tracks couldn't be added — see console for server details.")
            } catch {
                return classify(error)
            }

        case .moveItems:
            guard let p = try? decoder.decode(MoveItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed move_items payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil {
                #if DEBUG
                print("OutboxService: move_items skipped — local playlist \(p.playlistId) no longer exists")
                #endif
                return .success
            }
            #if DEBUG
            print("OutboxService: move_items firing — playlistId=\(p.playlistId), items=\(p.items.count)")
            #endif
            do {
                let moves = p.items.map { APIService.PositionedItemBody(itemId: $0.itemId, position: $0.position) }
                _ = try await api.updatePlaylistItems(p.playlistId, move: moves)
                return .success
            } catch APIError.httpError(422) {
                return .discard("Couldn't reorder — input rejected by the server.")
            } catch APIError.httpError(400) {
                return .discard("Couldn't reorder — see console for server details.")
            } catch {
                return classify(error)
            }

        case .removeItems:
            guard let p = try? decoder.decode(RemoveItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed remove_items payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil {
                #if DEBUG
                print("OutboxService: remove_items skipped — local playlist \(p.playlistId) no longer exists")
                #endif
                return .success
            }
            do {
                _ = try await api.updatePlaylistItems(p.playlistId, remove: p.itemIds)
                return .success
            } catch APIError.httpError(404) {
                return .success  // playlist/items already gone, local removal was correct
            } catch APIError.httpError(400) {
                return .discard("Some tracks couldn't be removed — see console for server details.")
            } catch {
                return classify(error)
            }
        }
    }

    /// Classifies an error into the right retry outcome. URL errors (offline, timeout, unreachable)
    /// and expired auth shouldn't burn through the retry cap — they resolve themselves externally.
    private func classify(_ error: Error) -> Outcome {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
            return .retryNoPenalty("Session expired — waiting for re-authentication")
        }
        if let urlError = error as? URLError {
            return .retryNoPenalty(urlError.localizedDescription)
        }
        return .retry(error.localizedDescription)
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
