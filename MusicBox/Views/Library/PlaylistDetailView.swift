import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(PlaylistController.self) private var controller
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network
    @Environment(SyncService.self) private var syncService
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    /// Read the NavigationStack-provided edit-mode binding so EditButton works with no
    /// explicit setup on our side.
    @Environment(\.editMode) private var editMode
    #endif

    let playlist: Playlist

    @State private var tracks: [Track] = []
    @State private var items: [PlaylistItem] = []
    @State private var trackByItemId: [UUID: Track] = [:]
    @State private var currentName: String
    @State private var hasLoadedOnce: Bool = false
    @State private var showRename = false
    @State private var showMove = false
    @State private var showDeleteConfirm = false
    @State private var showCancelDownloads = false
    #if os(iOS)
    /// Selected PlaylistItem.ids while in edit mode — drives the bulk-action bar.
    @State private var selection: Set<UUID> = []
    #endif

    init(playlist: Playlist) {
        self.playlist = playlist
        self._currentName = State(initialValue: playlist.name)
    }

    private var hasPlayable: Bool {
        guard !tracks.isEmpty else { return false }
        if network.isOnline { return true }
        return tracks.contains { $0.isDownloaded }
    }

    private var isFullyDownloaded: Bool {
        !tracks.isEmpty && tracks.allSatisfy { $0.isDownloaded }
    }

    private var allTrackIds: Set<UUID> { Set(tracks.map(\.id)) }

    private var isPlaylistDownloading: Bool {
        tracks.contains { downloadService.isDownloading(trackId: $0.id) || downloadService.isQueued(trackId: $0.id) }
    }

    private func cancelPlaylistDownloads() {
        for track in tracks where downloadService.isDownloading(trackId: track.id) || downloadService.isQueued(trackId: track.id) {
            downloadService.cancelDownload(trackId: track.id)
        }
    }

    /// Queue items built with each playlist item's id as the `QueueItem.id`. This lets us tell
    /// "the third occurrence of track A" apart from "the fifth occurrence" when highlighting
    /// the currently-playing row.
    private func buildQueueItems() -> [QueueItem] {
        zip(items, tracks).map { item, track in
            QueueItem(id: item.id, track: track, artworkURL: track.album?.artworkUrl)
        }
    }

    private func availableQueueItems() -> [QueueItem] {
        buildQueueItems().filter { network.isOnline || $0.track.isDownloaded }
    }

    private func isItemPlaying(_ item: PlaylistItem) -> Bool {
        guard player.queue.indices.contains(player.effectiveIndex) else { return false }
        return player.queue[player.effectiveIndex].id == item.id
    }

    var body: some View {
        listBody
            .listStyle(.plain)
            .navigationTitle(currentName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showRename = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            showMove = true
                        } label: {
                            Label("Move to Folder…", systemImage: "folder")
                        }

                        if !tracks.isEmpty {
                            if isFullyDownloaded {
                                Button(role: .destructive) {
                                    controller.disableAutoDownloadAndRemove(playlist.id)
                                } label: {
                                    Label("Remove Download", systemImage: "trash")
                                }
                            } else {
                                Button {
                                    controller.enableAutoDownload(playlist.id)
                                } label: {
                                    Label("Download", systemImage: "arrow.down.circle")
                                }
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showRename) {
                PlaylistNameSheet(mode: .rename(initialName: currentName)) { name in
                    controller.renamePlaylist(playlist.id, name: name)
                    currentName = name
                }
            }
            .sheet(isPresented: $showMove) {
                MovePlaylistSheet(playlist: musicLibrary.playlist(playlist.id) ?? playlist)
            }
            .confirmationDialog(
                "Delete \(currentName)?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    controller.deletePlaylist(playlist.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the playlist.")
            }
            .confirmationDialog("Cancel Downloads", isPresented: $showCancelDownloads) {
                Button("Cancel All Downloads", role: .destructive) {
                    cancelPlaylistDownloads()
                }
            } message: {
                Text("Cancel all pending and active downloads for this playlist?")
            }
            .overlay {
                if hasLoadedOnce && tracks.isEmpty {
                    ContentUnavailableView("Empty Playlist", systemImage: "music.note.list")
                }
            }
            .onChange(of: musicLibrary.revision, initial: true) {
                reloadTracks()
            }
            .onChange(of: musicLibrary.downloadChanged) {
                musicLibrary.applyDownloadChanges(to: &tracks)
                // The view reads tracks via `trackByItemId` now — keep it in sync so the
                // download icon flips live as downloads complete.
                trackByItemId = Dictionary(uniqueKeysWithValues: zip(items, tracks).map { ($0.0.id, $0.1) })
            }
    }

    // MARK: - List body (selection binding differs per platform)

    @ViewBuilder
    private var listBody: some View {
        #if os(iOS)
        List(selection: $selection) {
            headerSection
            itemsSection
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            selectionMenu(for: ids)
        }
        #else
        List {
            headerSection
            itemsSection
        }
        #endif
    }

    #if os(iOS)
    /// Menu shown when long-pressing in edit mode. `ids` is the selection if the pressed row
    /// is selected (or just the pressed row's id otherwise).
    @ViewBuilder
    private func selectionMenu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button {
                let items = queueItems(for: ids)
                guard !items.isEmpty else { return }
                player.playNext(queue: items)
                exitSelection()
            } label: {
                Label(ids.count == 1 ? "Play Next" : "Play \(ids.count) Next",
                      systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                let items = queueItems(for: ids)
                guard !items.isEmpty else { return }
                player.addToEnd(queue: items)
                exitSelection()
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            Button {
                let trackIds = selectedItemsInOrder(for: ids).map { $0.0.trackId }
                guard !trackIds.isEmpty else { return }
                NotificationCenter.default.post(name: .requestAddToPlaylist, object: trackIds)
                exitSelection()
            } label: {
                Label("Add to Playlist…", systemImage: "music.note.list")
            }
            Divider()
            Button {
                moveSelectionToTop(ids)
                exitSelection()
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            Button {
                moveSelectionToBottom(ids)
                exitSelection()
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            Divider()
            Button(role: .destructive) {
                for id in ids {
                    controller.removeItem(id, from: playlist.id)
                }
                exitSelection()
            } label: {
                Label(ids.count == 1 ? "Remove" : "Remove \(ids.count)", systemImage: "minus.circle")
            }
        }
    }

    private func selectedItemsInOrder(for ids: Set<UUID>) -> [(PlaylistItem, Track)] {
        zip(items, tracks).compactMap { item, track in
            ids.contains(item.id) ? (item, track) : nil
        }
    }

    private func queueItems(for ids: Set<UUID>) -> [QueueItem] {
        selectedItemsInOrder(for: ids)
            .filter { network.isOnline || $0.1.isDownloaded }
            .map { item, track in QueueItem(id: item.id, track: track, artworkURL: track.album?.artworkUrl) }
    }

    /// Moves the given selection to the top of the playlist, preserving their relative order.
    private func moveSelectionToTop(_ ids: Set<UUID>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let firstUnselectedPos = items.first(where: { !ids.contains($0.id) })?.position
        guard let positions = computePositions(count: selected.count, between: nil, and: firstUnselectedPos) else {
            abortReorderAndResync()
            return
        }
        for (item, newPos) in zip(selected, positions) {
            controller.moveItem(item.id, to: newPos, within: playlist.id)
        }
    }

    /// Moves the given selection to the bottom of the playlist, preserving their relative order.
    private func moveSelectionToBottom(_ ids: Set<UUID>) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let lastUnselectedPos = items.last(where: { !ids.contains($0.id) })?.position
        guard let positions = computePositions(count: selected.count, between: lastUnselectedPos, and: nil) else {
            abortReorderAndResync()
            return
        }
        for (item, newPos) in zip(selected, positions) {
            controller.moveItem(item.id, to: newPos, within: playlist.id)
        }
    }
    #endif

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentName)
                    .font(.title2.bold())

                Text("^[\(tracks.count) song](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        let available = availableQueueItems()
                        player.requestPlay { player.playNow(queue: available) }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                            .frame(width: 18, height: 18)
                    }
                    .disabled(!hasPlayable)

                    Button {
                        let available = availableQueueItems()
                        player.requestPlay { player.playShuffled(queue: available) }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13))
                            .frame(width: 18, height: 18)
                    }
                    .disabled(!hasPlayable)

                    if !tracks.isEmpty {
                        if isPlaylistDownloading {
                            Button {
                                showCancelDownloads = true
                            } label: {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 18, height: 18)
                            }
                        } else if !isFullyDownloaded {
                            Button {
                                controller.enableAutoDownload(playlist.id)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 13))
                                    .frame(width: 18, height: 18)
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .offset(x: -4)
                .padding(.top, 4)
            }
            .listRowSeparator(.hidden)
        }
    }

    private var itemsSection: some View {
        Section {
            // Iterate `items` directly (PlaylistItem is Identifiable with unique UUID) so
            // List(selection:) can auto-tag rows. Using enumerated tuples broke selection.
            ForEach(items) { item in
                if let track = trackByItemId[item.id] {
                    TrackRow(
                        track: track,
                        showArtist: true,
                        showArtwork: true,
                        showNumber: false,
                        onTap: {
                            let available = availableQueueItems()
                            if let startIndex = available.firstIndex(where: { $0.id == item.id }) {
                                player.requestPlay { player.playNow(queue: available, startingAt: startIndex) }
                            }
                        },
                        isCurrentlyPlaying: isItemPlaying(item)
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            controller.removeItem(item.id, from: playlist.id)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
            }
            .onMove(perform: handleMove)
        }
    }

    #if os(iOS)
    private func exitSelection() {
        selection.removeAll()
        editMode?.wrappedValue = .inactive
    }
    #endif

    // MARK: - Reorder

    /// Supports both single-item and multi-item drags. `.move(fromOffsets:toOffset:)` already
    /// preserves the moved items' relative order, so they land as a contiguous block in the
    /// destination. We spread fresh fractional positions across that block.
    private func handleMove(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        Haptics.light()

        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)

        let movingIds = Set(source.map { items[$0].id })
        guard let firstMovedIndex = reordered.firstIndex(where: { movingIds.contains($0.id) }) else { return }
        let blockCount = source.count
        let lastMovedIndex = firstMovedIndex + blockCount - 1

        let beforePos = firstMovedIndex > 0 ? reordered[firstMovedIndex - 1].position : nil
        let afterPos  = lastMovedIndex < reordered.count - 1 ? reordered[lastMovedIndex + 1].position : nil

        guard let newPositions = computePositions(count: blockCount, between: beforePos, and: afterPos) else {
            abortReorderAndResync()
            return
        }

        for (offset, pos) in newPositions.enumerated() {
            let item = reordered[firstMovedIndex + offset]
            controller.moveItem(item.id, to: pos, within: playlist.id)
        }
    }

    /// Spreads `count` fresh fractional positions strictly between `left` and `right`. Returns
    /// nil if either neighbor is malformed — local data has drifted from a server-side format
    /// our `FractionalIndex` doesn't recognize. Caller should bail out and resync.
    private func computePositions(count: Int, between left: String?, and right: String?) -> [String]? {
        do {
            var result: [String] = []
            result.reserveCapacity(count)
            var cursor = left
            for _ in 0..<count {
                let pos = try FractionalIndex.betweenThrowing(cursor, right)
                result.append(pos)
                cursor = pos
            }
            return result
        } catch {
            #if DEBUG
            print("PlaylistDetailView: cannot compute positions between \(left ?? "nil") and \(right ?? "nil"): \(error)")
            #endif
            return nil
        }
    }

    /// Snaps the list back to its previous order (we never wrote the move) and pulls a fresh
    /// sync, which should overwrite the malformed positions.
    private func abortReorderAndResync() {
        reloadTracks()
        Task { await syncService.sync() }
    }

    private func reloadTracks() {
        items = musicLibrary.playlistItems(playlist.id)
        let allTracks = musicLibrary.tracksForPlaylist(playlist.id)
        // tracksForPlaylist skips missing-from-library items, so filter `items` to match.
        let trackIds = Set(allTracks.map(\.id))
        items = items.filter { trackIds.contains($0.trackId) }
        tracks = allTracks
        trackByItemId = Dictionary(uniqueKeysWithValues: zip(items, tracks).map { ($0.0.id, $0.1) })
        hasLoadedOnce = true

        // Also refresh the display name in case sync applied a rename.
        if let refreshed = musicLibrary.playlist(playlist.id) {
            currentName = refreshed.name
        }
    }
}
