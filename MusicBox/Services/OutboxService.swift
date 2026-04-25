import Foundation

/// Durable replay queue for playlist mutations. UI writes to the local store synchronously
/// and enqueues the corresponding op here; this service drains the queue whenever a network
/// path is available.
///
/// Temp UUIDs minted by the UI for create_playlist / add_items are swapped for server-assigned
/// UUIDs on successful replay, both in the local SwiftData store and in downstream payloads
/// still waiting in the queue.
///
/// Item-level ops (add/move/remove) coalesce at flush time: adjacent mutations targeting the
/// same playlist merge into one API call — across kinds too, since PATCH /items takes all
/// three arrays — capped at `maxOperationsPerBatch`. A move/remove referencing a temp id whose
/// add is in the same batch would fail (server doesn't know the temp id yet), so those break
/// the batch and run in separate flushes.
@Observable
final class OutboxService {
    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let api: APIService

    var pendingCount: Int = 0
    var lastError: String?

    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    /// After this many transient failures in a row, escalate to a discard so one bad mutation
    /// can't permanently block the queue.
    @ObservationIgnored private let maxRetryAttempts = 20
    /// Server accepts up to 250 operations per PATCH /items request.
    @ObservationIgnored private let maxOperationsPerBatch = 250
    /// Bound on the filter-and-retry recursion for `unknown_tracks` / `unknown_items`.
    @ObservationIgnored private let maxFilterRetries = 3

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

        while let head = musicLibrary.pendingMutations().first {
            let consumed: [PendingMutation]
            let outcome: Outcome

            if let batch = collectBatch(from: musicLibrary.pendingMutations()) {
                #if DEBUG
                if batch.consumed.count > 1 {
                    print("OutboxService: batched \(batch.summary) — \(batch.consumed.count) mutations, \(batch.operationCount) ops")
                }
                #endif
                consumed = batch.consumed
                outcome = await processBatch(batch)
            } else {
                consumed = [head]
                outcome = await process(head)
            }

            if !applyOutcome(outcome, head: head, consumedOnSuccess: consumed) {
                return
            }
        }
    }

    private func applyOutcome(_ outcome: Outcome, head: PendingMutation, consumedOnSuccess: [PendingMutation]) -> Bool {
        switch outcome {
        case .success:
            #if DEBUG
            print("OutboxService: \(head.kind) succeeded (\(consumedOnSuccess.count) mutation\(consumedOnSuccess.count == 1 ? "" : "s"))")
            #endif
            for mutation in consumedOnSuccess {
                musicLibrary.deletePendingMutation(mutation)
            }
            refreshPendingCount()
            return true
        case .discard(let reason):
            #if DEBUG
            print("OutboxService: \(head.kind) discarded — \(reason)")
            #endif
            lastError = reason
            musicLibrary.deletePendingMutation(head)
            refreshPendingCount()
            return true
        case .retry(let reason):
            head.attemptCount += 1
            head.lastError = reason
            head.lastAttemptAt = Date()
            if head.attemptCount >= maxRetryAttempts {
                #if DEBUG
                print("OutboxService: \(head.kind) giving up after \(head.attemptCount) attempts — \(reason)")
                #endif
                lastError = "A playlist change couldn't sync: \(reason)"
                musicLibrary.deletePendingMutation(head)
                refreshPendingCount()
                return true
            }
            #if DEBUG
            print("OutboxService: \(head.kind) retry (attempt \(head.attemptCount)) — \(reason)")
            #endif
            musicLibrary.persistChanges()
            refreshPendingCount()
            scheduleRetry()
            return false
        case .retryNoPenalty(let reason):
            head.lastError = reason
            head.lastAttemptAt = Date()
            #if DEBUG
            print("OutboxService: \(head.kind) paused (no-penalty) — \(reason)")
            #endif
            musicLibrary.persistChanges()
            refreshPendingCount()
            scheduleRetry()
            return false
        }
    }

    // MARK: - Batching

    private struct Batch {
        let playlistId: UUID
        let consumed: [PendingMutation]
        let addEntries: [AddItemsPayload.Entry]
        let moveEntries: [MoveItemsPayload.Entry]
        let removeIds: [UUID]

        var operationCount: Int { addEntries.count + moveEntries.count + removeIds.count }
        var summary: String {
            var parts: [String] = []
            if !addEntries.isEmpty { parts.append("add=\(addEntries.count)") }
            if !moveEntries.isEmpty { parts.append("move=\(moveEntries.count)") }
            if !removeIds.isEmpty { parts.append("remove=\(removeIds.count)") }
            return parts.joined(separator: " ")
        }
    }

    /// Walks from the head collecting adjacent item-level mutations (add/move/remove) for the same
    /// playlist into a single multi-op batch. Stops at: different playlist, op cap reached, a
    /// move/remove that references a temp id whose add is in this same batch (the server doesn't
    /// know that id yet), or a non-batchable kind.
    private func collectBatch(from mutations: [PendingMutation]) -> Batch? {
        guard let head = mutations.first,
              let headKind = OutboxKind(rawValue: head.kind),
              isBatchableKind(headKind) else { return nil }

        let decoder = JSONDecoder()
        var consumed: [PendingMutation] = []
        var addEntries: [AddItemsPayload.Entry] = []
        var moveEntries: [MoveItemsPayload.Entry] = []
        var removeIds: [UUID] = []
        var playlistId: UUID?
        var opCount = 0
        var pendingAddItemIds: Set<UUID> = []  // temp ids in this batch's adds

        loop: for mutation in mutations {
            guard let mk = OutboxKind(rawValue: mutation.kind), isBatchableKind(mk) else { break }

            switch mk {
            case .addItems:
                guard let p = try? decoder.decode(AddItemsPayload.self, from: mutation.payload) else { break loop }
                if let existing = playlistId, existing != p.playlistId { break loop }
                if opCount + p.items.count > maxOperationsPerBatch { break loop }
                playlistId = p.playlistId
                addEntries.append(contentsOf: p.items)
                for entry in p.items { pendingAddItemIds.insert(entry.tempItemId) }
                opCount += p.items.count

            case .moveItems:
                guard let p = try? decoder.decode(MoveItemsPayload.self, from: mutation.payload) else { break loop }
                if let existing = playlistId, existing != p.playlistId { break loop }
                // A move of a temp item added in this batch would fail — server doesn't know
                // about it yet. Break so the add runs first, gets remapped, then move follows.
                if p.items.contains(where: { pendingAddItemIds.contains($0.itemId) }) { break loop }
                if opCount + p.items.count > maxOperationsPerBatch { break loop }
                playlistId = p.playlistId
                moveEntries.append(contentsOf: p.items)
                opCount += p.items.count

            case .removeItems:
                guard let p = try? decoder.decode(RemoveItemsPayload.self, from: mutation.payload) else { break loop }
                if let existing = playlistId, existing != p.playlistId { break loop }
                if p.itemIds.contains(where: { pendingAddItemIds.contains($0) }) { break loop }
                if opCount + p.itemIds.count > maxOperationsPerBatch { break loop }
                playlistId = p.playlistId
                removeIds.append(contentsOf: p.itemIds)
                opCount += p.itemIds.count

            default:
                break loop
            }
            consumed.append(mutation)
        }

        guard !consumed.isEmpty, let pid = playlistId else { return nil }
        return Batch(playlistId: pid, consumed: consumed,
                     addEntries: addEntries, moveEntries: moveEntries, removeIds: removeIds)
    }

    private func isBatchableKind(_ kind: OutboxKind) -> Bool {
        kind == .addItems || kind == .moveItems || kind == .removeItems
    }

    private func processBatch(_ batch: Batch) async -> Outcome {
        if musicLibrary.playlist(batch.playlistId) == nil {
            #if DEBUG
            print("OutboxService: batched ops skipped — local playlist \(batch.playlistId) no longer exists")
            #endif
            return .success
        }
        return await executeItemOps(
            playlistId: batch.playlistId,
            addEntries: batch.addEntries,
            moveEntries: batch.moveEntries,
            removeIds: batch.removeIds,
            depth: 0
        )
    }

    // MARK: - Unified item-ops executor

    /// Runs one PATCH /items with the given combined payload. Recursive when the server returns
    /// `unknown_tracks` / `unknown_items` — we filter them out and retry up to `maxFilterRetries`.
    /// All single-mutation and batched paths ultimately flow through here.
    private func executeItemOps(
        playlistId: UUID,
        addEntries: [AddItemsPayload.Entry],
        moveEntries: [MoveItemsPayload.Entry],
        removeIds: [UUID],
        depth: Int
    ) async -> Outcome {
        if addEntries.isEmpty && moveEntries.isEmpty && removeIds.isEmpty { return .success }
        if depth >= maxFilterRetries {
            return .discard("Gave up after \(depth) filter retries.")
        }

        let adds = addEntries.map { APIService.PositionedTrackBody(trackId: $0.trackId, position: $0.position) }
        let moves = moveEntries.map { APIService.PositionedItemBody(itemId: $0.itemId, position: $0.position) }

        do {
            let response = try await api.updatePlaylistItems(playlistId, add: adds, move: moves, remove: removeIds)
            if !addEntries.isEmpty {
                let addedByPosition = Dictionary(uniqueKeysWithValues: response.added.map { ($0.position, $0) })
                for entry in addEntries {
                    if let confirmed = addedByPosition[entry.position] {
                        musicLibrary.swapLocalPlaylistItemId(tempId: entry.tempItemId, confirmed: confirmed)
                    }
                }
            }
            return .success
        } catch let error as APIService.PlaylistItemsError {
            return await recover(
                from: error,
                playlistId: playlistId,
                addEntries: addEntries,
                moveEntries: moveEntries,
                removeIds: removeIds,
                depth: depth
            )
        } catch APIError.httpError(422) {
            // Server returned 422 but the discriminated body didn't decode — fall back to discard.
            return .discard("Some changes were rejected by the server (422).")
        } catch APIError.httpError(404) where addEntries.isEmpty && moveEntries.isEmpty {
            // Playlist or items gone on a pure-remove call; local removal was still correct.
            return .success
        } catch {
            return classify(error)
        }
    }

    /// Filter-and-retry recovery for the two errors whose user intent is clear.
    private func recover(
        from error: APIService.PlaylistItemsError,
        playlistId: UUID,
        addEntries: [AddItemsPayload.Entry],
        moveEntries: [MoveItemsPayload.Entry],
        removeIds: [UUID],
        depth: Int
    ) async -> Outcome {
        switch error {
        case .unknownTracks(let badTrackIds):
            let badSet = Set(badTrackIds)
            let filtered = addEntries.filter { !badSet.contains($0.trackId) }
            if filtered.count == addEntries.count {
                // Server said unknown but none of our entries matched — something is off.
                return .discard("Some tracks couldn't be added — server rejected them.")
            }
            #if DEBUG
            print("OutboxService: dropped \(addEntries.count - filtered.count) unknown track(s); retrying")
            #endif
            return await executeItemOps(
                playlistId: playlistId,
                addEntries: filtered, moveEntries: moveEntries, removeIds: removeIds,
                depth: depth + 1
            )

        case .unknownItems(let badItemIds):
            let badSet = Set(badItemIds)
            let filteredMoves = moveEntries.filter { !badSet.contains($0.itemId) }
            let filteredRemoves = removeIds.filter { !badSet.contains($0) }
            if filteredMoves.count == moveEntries.count && filteredRemoves.count == removeIds.count {
                return .discard("Some playlist items couldn't be updated — server rejected them.")
            }
            #if DEBUG
            print("OutboxService: dropped \(moveEntries.count - filteredMoves.count) move(s) and \(removeIds.count - filteredRemoves.count) remove(s) referencing unknown items; retrying")
            #endif
            return await executeItemOps(
                playlistId: playlistId,
                addEntries: addEntries, moveEntries: filteredMoves, removeIds: filteredRemoves,
                depth: depth + 1
            )

        case .addMoveConflict:
            // Positions are algorithm-computed, so a collision means our local view of the
            // playlist's tail was stale (multi-device concurrency). Regenerate fresh positions
            // appended past the current local tail for everything in the request, reflect the
            // new move positions locally so the UI stays in sync, and retry.
            var cursor = musicLibrary.lastPlaylistItemPosition(playlistId)
            let newAdds: [AddItemsPayload.Entry] = addEntries.map { entry in
                let newPosition = FractionalIndex.after(cursor)
                cursor = newPosition
                return AddItemsPayload.Entry(tempItemId: entry.tempItemId, trackId: entry.trackId, position: newPosition)
            }
            let newMoves: [MoveItemsPayload.Entry] = moveEntries.map { entry in
                let newPosition = FractionalIndex.after(cursor)
                cursor = newPosition
                return MoveItemsPayload.Entry(itemId: entry.itemId, position: newPosition)
            }
            for entry in newMoves {
                musicLibrary.moveLocalPlaylistItem(itemId: entry.itemId, newPosition: entry.position)
            }
            #if DEBUG
            print("OutboxService: add_move_conflict — repositioned \(newAdds.count) add(s) + \(newMoves.count) move(s) past current tail; retrying")
            #endif
            return await executeItemOps(
                playlistId: playlistId,
                addEntries: newAdds, moveEntries: newMoves, removeIds: removeIds,
                depth: depth + 1
            )

        case .moveRemoveConflict(let conflictIds):
            // The same item was both moved and removed. Remove wins — drop the move.
            let conflictSet = Set(conflictIds)
            let filteredMoves = moveEntries.filter { !conflictSet.contains($0.itemId) }
            if filteredMoves.count == moveEntries.count {
                // Server flagged ids that weren't in our moves — can't self-heal.
                return .discard("A move and remove collided, but we couldn't identify which.")
            }
            #if DEBUG
            print("OutboxService: move_remove_conflict — dropping \(moveEntries.count - filteredMoves.count) conflicting move(s); retrying")
            #endif
            return await executeItemOps(
                playlistId: playlistId,
                addEntries: addEntries, moveEntries: filteredMoves, removeIds: removeIds,
                depth: depth + 1
            )

        case .tooManyOperations:
            // Our cap (maxOperationsPerBatch) should match the server's. Hitting this means
            // the server lowered its cap without the client being updated. Discard + surface
            // for now.
            //
            // Later improvement: split the batch (halve and retry) until it fits, and/or have
            // the server return its current limit in the error body so the client can adjust
            // `maxOperationsPerBatch` live. Needs a server-side API change.
            return .discard("Batch exceeded server op limit — client and server caps have drifted.")
        }
    }

    // MARK: - Single-mutation processing

    private enum Outcome {
        case success
        case retry(String)
        case retryNoPenalty(String)
        case discard(String)
    }

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
                return .success
            } catch {
                return classify(error)
            }

        case .addItems:
            guard let p = try? decoder.decode(AddItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed add_items payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil { return .success }
            return await executeItemOps(playlistId: p.playlistId,
                                         addEntries: p.items, moveEntries: [], removeIds: [],
                                         depth: 0)

        case .moveItems:
            guard let p = try? decoder.decode(MoveItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed move_items payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil { return .success }
            return await executeItemOps(playlistId: p.playlistId,
                                         addEntries: [], moveEntries: p.items, removeIds: [],
                                         depth: 0)

        case .removeItems:
            guard let p = try? decoder.decode(RemoveItemsPayload.self, from: mutation.payload) else {
                return .discard("Malformed remove_items payload")
            }
            if musicLibrary.playlist(p.playlistId) == nil { return .success }
            return await executeItemOps(playlistId: p.playlistId,
                                         addEntries: [], moveEntries: [], removeIds: p.itemIds,
                                         depth: 0)
        }
    }

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

    // MARK: - Compaction (called by PlaylistController on local delete/remove)

    /// Compacts the outbox after the user just deleted a playlist locally. Returns true when
    /// the deletion was fully absorbed by dropping a pending `create_playlist` — caller should
    /// skip enqueueing `delete_playlist`. Returns false otherwise (caller should enqueue).
    ///
    /// While a flush is in progress we can't safely strip a mid-roundtrip mutation, so this
    /// returns false and lets the normal delete enqueue happen.
    func compactForDeletedPlaylist(_ playlistId: UUID) -> Bool {
        guard !isFlushing else { return false }
        let absorbed = musicLibrary.compactPendingForDeletedPlaylist(playlistId)
        refreshPendingCount()
        return absorbed
    }

    /// Compacts the outbox after the user just removed item(s) locally. Returns the subset of
    /// `itemIds` that still need a `remove_items` roundtrip — the rest were stripped from
    /// pending `add_items` (server doesn't know those temp ids).
    func compactForRemovedItems(_ itemIds: [UUID]) -> [UUID] {
        guard !isFlushing, !itemIds.isEmpty else { return itemIds }
        let absorbed = musicLibrary.compactPendingForRemovedItems(Set(itemIds))
        refreshPendingCount()
        return itemIds.filter { !absorbed.contains($0) }
    }
}
