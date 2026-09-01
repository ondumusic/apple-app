#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Root macOS content view. SwiftUI shell that hosts the AppKit-backed sidebar,
/// track tables, toolbar, and mini-player. Layout fills in piece by piece — see
/// project_macos_rebuild_plan.md for the per-surface plan.
struct MacOSContentView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(PlaylistController.self) private var playlistController
    @Environment(DownloadService.self) private var downloadService

    @State private var showQueue = false
    @State private var sidebarSelection: SidebarSelection? = .category(.artists)
    /// Set when navigating to a specific artist (e.g. "Go to Artist" on a track).
    /// ArtistsViewMac reads it on its first load to skip the default first-artist
    /// selection — avoids the visible flicker the previous async re-post had.
    @State private var pendingArtistNavigation: UUID?
    @State private var detailPath = NavigationPath()
    @State private var deleteTarget: Playlist?
    @State private var addToPlaylistTrackIds: [UUID] = []
    @Environment(\.openWindow) private var openWindow
    @State private var searchText: String = ""
    /// Restored when a search is cleared — searching deselects the sidebar so it stops
    /// claiming you're still in whatever section you left.
    @State private var selectionBeforeSearch: SidebarSelection?
    /// Batch bookkeeping for the sidebar's progress bar. Queueing more work grows the
    /// total; finishing grows the completed count; both reset once the queue drains.
    @State private var batchTotal = 0
    @State private var batchCompleted = 0
    @State private var miniPlayer: MiniPlayerWindowController?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var spaceKeyMonitor: Any?
    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            Sidebar(
                selection: $sidebarSelection,
                searchText: $searchText,
                musicLibrary: musicLibrary,
                actions: sidebarActions,
                downloadingCount: downloadService.activeDownloads.count + downloadService.pendingQueue.count,
                downloadProgress: overallDownloadProgress,
                filter: $libraryFilter,
                accent: settings.resolvedAccentColor
            )
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                    if !searchText.isEmpty {
                        SearchViewMac(query: searchText)
                    } else {
                        DetailPlaceholder(selection: sidebarSelection, pendingArtistNavigation: $pendingArtistNavigation)
                    }
                }
                .navigationDestination(for: Album.self) { album in
                    AlbumDetailMac(album: album, backDestination: backDestination)
                }
                .navigationDestination(for: Artist.self) { artist in
                    ArtistDetailMac(artist: artist, backDestination: backDestination)
                }
                .navigationDestination(for: SearchAllRequest.self) { request in
                    SearchAllViewMac(request: request)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay(alignment: .trailing) { queueSlideOver }
        .animation(.easeInOut(duration: 0.22), value: showQueue)
        .queueConfirmationOverlay()
        .replaceQueueConfirmation()
        .removeDownloadConfirmation()
        .toolbar(removing: .sidebarToggle)
        .toolbar { PlayerToolbar(showQueue: $showQueue) }
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(
            isPresented: Binding(
                get: { !addToPlaylistTrackIds.isEmpty },
                set: { if !$0 { addToPlaylistTrackIds = [] } }
            )
        ) {
            AddToPlaylistSheet(trackIds: addToPlaylistTrackIds)
                .frame(minWidth: 420, minHeight: 420)
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { entry in
            Button(entry.isFolder ? "Delete Folder" : "Delete Playlist", role: .destructive) {
                playlistController.deletePlaylist(entry.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            if entry.isFolder {
                Text("This will permanently delete the folder and everything inside it.")
            } else {
                Text("This will permanently delete the playlist.")
            }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            // Switching sidebar items resets the drill-in stack so we don't show stale
            // album/artist detail under a new section.
            detailPath = NavigationPath()
            // Picking a section is a way out of search, the same as clearing the field.
            if newValue != nil, !searchText.isEmpty {
                searchText = ""
                selectionBeforeSearch = nil
            }
        }
        .onChange(of: downloadsRemaining) { previous, current in
            if current == 0 {
                batchTotal = 0
                batchCompleted = 0
            } else if current < previous {
                batchCompleted += previous - current
            } else {
                batchTotal += current - previous
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if newValue.isEmpty {
                guard !oldValue.isEmpty else { return }
                sidebarSelection = selectionBeforeSearch ?? .category(.artists)
                selectionBeforeSearch = nil
            } else if oldValue.isEmpty {
                selectionBeforeSearch = sidebarSelection
                sidebarSelection = nil
            } else {
                // Refining the query drops any "show all" drill-in — it was built from
                // the previous query and would otherwise sit there showing stale results.
                detailPath = NavigationPath()
            }
        }
        .onChange(of: sidebarVisibility) { _, newValue in
            // We don't allow the sidebar to be hidden — clamp back to .all if anything
            // (toolbar button, View menu, keyboard shortcut) tries to collapse it.
            if newValue != .all {
                sidebarVisibility = .all
            }
        }
        .onAppear {
            installSpaceKeyMonitor()
            // Reopen the mini player if it was showing when the app last quit, in
            // whichever z-order and focus the user left the two windows in.
            if UserDefaults.standard.bool(forKey: MiniPlayerWindowController.visibleDefaultsKey) {
                let mp = miniPlayer ?? MiniPlayerWindowController(player: player, settings: settings)
                miniPlayer = mp
                mp.restoreAtLaunch()
            }
        }
        .onDisappear {
            if let spaceKeyMonitor { NSEvent.removeMonitor(spaceKeyMonitor) }
            spaceKeyMonitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
            toggleMiniPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDownloadActivity)) { _ in
            openWindow(id: "activity")
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
            player.togglePlayPause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            detailPath.append(album)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            if !searchText.isEmpty {
                // Push, so there's a way back to the results. Switching sections here
                // clears the search and strands you with nothing to return to.
                detailPath.append(artist)
                return
            }
            // Otherwise land in the Artists category on that artist. The
            // pendingArtistNavigation binding lets ArtistsViewMac skip its default
            // first-artist selection on first mount (no flicker).
            pendingArtistNavigation = artist.id
            sidebarSelection = .category(.artists)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestAddToPlaylist)) { notification in
            guard let ids = notification.object as? [UUID], !ids.isEmpty else { return }
            addToPlaylistTrackIds = ids
        }
    }

    /// Space toggles playback, but only when nothing is taking text input. A menu key
    /// equivalent can't make that distinction — it fires while the search field has
    /// focus — and a bare `.keyboardShortcut` never arrives at all once a list is first
    /// responder, because the list consumes the key first.
    private func installSpaceKeyMonitor() {
        guard spaceKeyMonitor == nil else { return }
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let spaceKeyCode: UInt16 = 49
            guard event.keyCode == spaceKeyCode,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            return nil
        }
    }

    /// Posts the inline-rename trigger for a freshly-created playlist/folder. The
    /// outbox can flush + remap the temp id to the real id within a few ms — faster
    /// than SwiftUI's tree rebuild — so we listen for .playlistIdRemapped during the
    /// settle window and post whichever id is current. If the remap doesn't happen
    /// (offline), we post the temp id at the timeout.
    private func scheduleInlineRename(forTempId tempId: UUID) {
        var posted = false
        var observer: NSObjectProtocol?
        let post: (UUID) -> Void = { id in
            guard !posted else { return }
            posted = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            #if DEBUG
            print("[rename] posting startInlineRename for id=\(id)")
            #endif
            NotificationCenter.default.post(name: .startInlineRename, object: id)
        }
        observer = NotificationCenter.default.addObserver(
            forName: .playlistIdRemapped,
            object: nil,
            queue: .main
        ) { note in
            guard let info = note.userInfo,
                  let temp = info["temp"] as? UUID, temp == tempId,
                  let real = info["real"] as? UUID
            else { return }
            #if DEBUG
            print("[rename] remap caught: \(temp) → \(real)")
            #endif
            post(real)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            post(tempId)
        }
    }

    private var downloadsRemaining: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
    }

    /// Progress across the whole batch, not across the current workers. Averaging the
    /// in-flight fractions made the bar sawtooth: each completion took a ~1.0 out of the
    /// numerator while a queued item entered at 0, so finishing something moved the bar
    /// backwards. Counting finished items keeps it monotonic — the completion adds 1 to
    /// `batchCompleted` at the same moment its fraction leaves `partial`.
    private var overallDownloadProgress: Double {
        guard batchTotal > 0 else { return 0 }
        let partial = downloadService.activeDownloads.keys
            .reduce(0.0) { $0 + (downloadService.progressSnapshot[$1] ?? 0) }
        return min(1, (Double(batchCompleted) + partial) / Double(batchTotal))
    }

    private func toggleMiniPlayer() {
        if let mp = miniPlayer {
            mp.toggle()
        } else {
            let mp = MiniPlayerWindowController(player: player, settings: settings)
            miniPlayer = mp
            mp.showWindow(nil)
            UserDefaults.standard.set(true, forKey: MiniPlayerWindowController.visibleDefaultsKey)
        }
    }

    /// Slide-over queue panel — overlays detail content from the right edge, doesn't
    /// push other content away. Side-by-side HStack so the dismiss area is genuinely
    /// separate from the panel (no invisible click-catcher overlapping the list).
    @ViewBuilder
    private var queueSlideOver: some View {
        if showQueue {
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { showQueue = false }
                QueuePanel(isPresented: $showQueue)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: -2, y: 0)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    /// What a pushed detail view returns to — the search results if that's where the
    /// push came from, otherwise the section that's selected.
    private var backDestination: String {
        if !searchText.isEmpty { return "Search" }
        switch sidebarSelection {
        case .category(let category): return category.title
        case .playlist(let id): return musicLibrary.playlist(id)?.name ?? "Library"
        case nil: return "Library"
        }
    }

    private var sidebarActions: SidebarActions {
        var a = SidebarActions()
        a.downloadPlaylist = { [musicLibrary, downloadService] playlist in
            let ids = Set(musicLibrary.tracksForPlaylist(playlist.id).map(\.id))
            guard !ids.isEmpty else { return }
            downloadService.downloadTracks(ids: ids, library: musicLibrary)
        }
        a.removePlaylistDownload = { [musicLibrary] playlist in
            let ids = Set(musicLibrary.tracksForPlaylist(playlist.id).filter(\.isDownloaded).map(\.id))
            DownloadRemovalRequest.post(trackIds: ids, subject: playlist.name)
        }
        a.isPlaylistDownloaded = { [musicLibrary] playlist in
            let tracks = musicLibrary.tracksForPlaylist(playlist.id)
            return !tracks.isEmpty && tracks.allSatisfy(\.isDownloaded)
        }
        a.playPlaylist = { playlist in
            let tracks = musicLibrary.tracksForPlaylist(playlist.id)
            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playNow(tracks: available) }
        }
        a.shufflePlaylist = { playlist in
            let tracks = musicLibrary.tracksForPlaylist(playlist.id)
            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
            guard !available.isEmpty else { return }
            player.requestPlay { player.playShuffled(tracks: available) }
        }
        a.renamePlaylist = { playlist, newName in
            playlistController.renamePlaylist(playlist.id, name: newName)
        }
        a.deletePlaylist = { playlist in
            deleteTarget = playlist
        }
        a.addTracksToPlaylist = { trackIds, playlist in
            playlistController.addTracks(trackIds, to: playlist.id)
        }
        a.createPlaylist = { parentId in
            guard let new = playlistController.createPlaylist(name: "Untitled Playlist", parentId: parentId) else { return }
            scheduleInlineRename(forTempId: new.id)
        }
        a.createFolder = { parentId in
            guard let new = playlistController.createFolder(name: "New Folder", parentId: parentId) else { return }
            scheduleInlineRename(forTempId: new.id)
        }
        a.movePlaylist = { playlistId, parentId in
            playlistController.movePlaylist(playlistId, to: parentId)
        }
        return a
    }
}

private struct DetailPlaceholder: View {
    let selection: SidebarSelection?
    @Binding var pendingArtistNavigation: UUID?

    var body: some View {
        switch selection {
        case .category(.songs):
            SongsViewMac()
        case .category(.albums):
            AlbumsViewMac()
        case .category(.artists):
            ArtistsViewMac(pendingArtistSelection: $pendingArtistNavigation)
        case .category(.downloads):
            DownloadsViewMac()
        case .playlist(let id):
            PlaylistDetailMac(playlistId: id)
                .id(id)
        case .none:
            ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
        }
    }
}

/// Slide-over queue panel — anchored to the right edge of the window, overlays
/// detail content (no push). Shows the "up next" portion of the queue with
/// artwork thumbnails. Each row has a visible trash button (remove); double-
/// click skips to the track; right-click for context menu.
struct QueuePanel: View {
    @Environment(PlayerService.self) private var player
    @Binding var isPresented: Bool

    private var upNext: [(originalIndex: Int, item: QueueItem)] { player.upNextEntries }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.secondary.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            if upNext.isEmpty {
                ContentUnavailableView(
                    "Nothing Up Next",
                    systemImage: "list.bullet",
                    description: Text("Add tracks to the queue to see them here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                QueueList(upNext: upNext, rowHeight: 48, showsDuration: true)
            }
        }
    }
}

/// Reusable queue list — used by both the main slide-over and the mini player's
/// inline panel. ScrollView + LazyVStack with selection (click + cmd-click),
/// per-row hover-revealed Remove, double-click to skip, drag-to-reorder with
/// insertion-line indicator, multi-drag of selected items.
struct QueueList: View {
    @Environment(PlayerService.self) private var player

    let upNext: [(originalIndex: Int, item: QueueItem)]
    let rowHeight: CGFloat
    let showsDuration: Bool

    @State private var selection: Set<UUID> = []
    @State private var hoveredId: UUID?
    @State private var dropTargetId: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(upNext, id: \.item.id) { entry in
                    QueueListRow(
                        originalIndex: entry.originalIndex,
                        item: entry.item,
                        isHovered: hoveredId == entry.item.id,
                        isSelected: selection.contains(entry.item.id),
                        isDropTarget: dropTargetId == entry.item.id,
                        showsDuration: showsDuration,
                        onTap: { handleTap(entry) },
                        onRemove: { remove(entry) }
                    )
                    .onHover { hovering in
                        if hovering { hoveredId = entry.item.id }
                        else if hoveredId == entry.item.id { hoveredId = nil }
                    }
                    .draggable(payload(for: entry))
                    .dropDestination(for: QueueDragPayload.self) { payloads, _ in
                        defer { dropTargetId = nil }
                        guard let payload = payloads.first else { return false }
                        let sources = IndexSet(payload.originalIndices)
                        guard !sources.isEmpty,
                              !payload.itemIds.contains(entry.item.id)
                        else { return false }
                        player.moveQueueItems(from: sources, to: entry.originalIndex)
                        return true
                    } isTargeted: { hovering in
                        if hovering { dropTargetId = entry.item.id }
                        else if dropTargetId == entry.item.id { dropTargetId = nil }
                    }
                    Divider().opacity(0.5)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func payload(for entry: (originalIndex: Int, item: QueueItem)) -> QueueDragPayload {
        // Drag the whole selection if the dragged row is part of it; otherwise
        // just the dragged row.
        if selection.contains(entry.item.id), selection.count > 1 {
            let entries = upNext.filter { selection.contains($0.item.id) }
            return QueueDragPayload(
                itemIds: entries.map { $0.item.id },
                originalIndices: entries.map { $0.originalIndex }
            )
        }
        return QueueDragPayload(itemIds: [entry.item.id], originalIndices: [entry.originalIndex])
    }

    private func handleTap(_ entry: (originalIndex: Int, item: QueueItem)) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selection.contains(entry.item.id) {
                selection.remove(entry.item.id)
            } else {
                selection.insert(entry.item.id)
            }
        } else if modifiers.contains(.shift), let last = selection.first,
                  let lastIdx = upNext.firstIndex(where: { $0.item.id == last }),
                  let curIdx = upNext.firstIndex(where: { $0.item.id == entry.item.id }) {
            let lo = min(lastIdx, curIdx)
            let hi = max(lastIdx, curIdx)
            selection.formUnion(upNext[lo...hi].map(\.item.id))
        } else {
            selection = [entry.item.id]
        }
    }

    private func remove(_ entry: (originalIndex: Int, item: QueueItem)) {
        // If the removed row is in the selection, remove all selected — otherwise
        // remove just this one.
        let targets: [Int]
        if selection.contains(entry.item.id) {
            targets = upNext.filter { selection.contains($0.item.id) }.map(\.originalIndex)
            selection.removeAll()
        } else {
            targets = [entry.originalIndex]
        }
        player.removeFromQueue(at: IndexSet(targets))
    }
}

/// Pasteboard payload used for in-queue drag-to-reorder. Carries one or more
/// item ids + their original queue indices so multi-drag works.
struct QueueDragPayload: Codable, Transferable {
    let itemIds: [UUID]
    let originalIndices: [Int]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// One queue row. Title + artist + (optional) duration + remove button. Visual
/// states: hover (subtle bg), selected (accent tint), drop target (top insertion
/// line).
struct QueueListRow: View {
    @Environment(PlayerService.self) private var player
    let originalIndex: Int
    let item: QueueItem
    let isHovered: Bool
    let isSelected: Bool
    let isDropTarget: Bool
    let showsDuration: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(url: item.artworkURL, cornerRadius: 3)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.track.name)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(item.track.artist.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showsDuration && !isHovered {
                Text(item.track.formattedDuration)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(rowBackground)
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .onTapGesture(count: 2) {
            player.skipTo(queueIndex: originalIndex)
        }
        .simultaneousGesture(TapGesture().onEnded { onTap() })
        .contextMenu {
            Button("Play") {
                player.skipTo(queueIndex: originalIndex)
            }
            Button(role: .destructive, action: onRemove) {
                Label(isSelected ? "Remove Selected" : "Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor
        } else if isHovered {
            Color.secondary.opacity(0.08)
        } else {
            Color.clear
        }
    }
}
#endif
