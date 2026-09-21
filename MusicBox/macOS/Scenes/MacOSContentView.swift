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
    /// Restored from the last session — reopening on Artists every time loses your place.
    @State private var sidebarSelection: SidebarSelection? = MacOSContentView.restoredSelection()
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
    @AppStorage("macSidebarWidth") private var sidebarWidth: Double = 240
    /// Drives the toolbar's search field for Cmd+F. Search moved out of the sidebar.
    @FocusState private var searchFieldFocused: Bool
    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all

    var body: some View {
        // The window draws under its titlebar, but SwiftUI reserves the strip until told
        // otherwise — measured without this, the player row sat 39pt below the window top
        // and the sidebar 80pt, where Music.app's sit at 0 and 52. It has to be outermost:
        // applied part-way down the chain it grows that view past the window's top edge
        // instead, and the row gets clipped.
        splitViewChrome
            .ignoresSafeArea(.container, edges: .top)
    }

    private var splitView: some View {
        HStack(spacing: 0) {
            Sidebar(
                selection: $sidebarSelection,
                searchText: $searchText,
                musicLibrary: musicLibrary,
                actions: sidebarActions,
                downloadingCount: downloadService.activeDownloads.count + downloadService.pendingQueue.count,
                downloadProgress: overallDownloadProgress,
                accent: settings.resolvedAccentColor
            )
            .frame(width: sidebarWidth)

            SidebarDivider(width: $sidebarWidth, range: 200...360)

            // A plain VStack lays out here, unlike inside NavigationSplitView's detail
            // column where a sibling never got laid out at all. So the player row simply
            // sits above the content and the content starts below it — no overlay, no
            // reserved insets, no scroller to lift clear.
            VStack(spacing: 0) {
                PlayerBar(showQueue: $showQueue)
                GeometryReader { geo in
                    // Music pushes Up Next aside only while enough content survives, and
                    // floats it over the content when it wouldn't — measured by toggling
                    // theirs across widths: it pushes at a 1300pt window and overlays at
                    // 1275, the switch landing where the remaining column would drop
                    // below about 790pt for their 300pt panel.
                    let pushes = showQueue
                        && geo.size.width - Self.queueWidth >= Self.queuePushMinContent
                    HStack(spacing: 0) {
                        detailStack
                        if pushes {
                            Divider()
                            QueuePanel(isPresented: $showQueue)
                                .frame(width: Self.queueWidth)
                        }
                    }
                    // A push happens instantly. Animating the column's width meant the
                    // AppKit grid and tables were re-laid out on every frame, and row
                    // heights shift as the width does — mid-slide the top of an artist's
                    // list would show a different album and then settle back. Sliding the
                    // panel while the content snapped was worse again. The overlay below
                    // still slides: nothing resizes for it.
                    .animation(nil, value: showQueue)
                    // Only the floating panel casts a shadow; a pushed one is tiled
                    // beside the content and has nothing to lift off.
                    .overlay(alignment: .trailing) {
                        if !pushes { queueOverlay(visible: showQueue) }
                    }
                    // On the content, not the window: it anchors to the top of whatever
                    // it's attached to, which at window level is now the player row.
                    .queueConfirmationOverlay()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailStack: some View {
        Group {
            NavigationStack(path: $detailPath) {
                Group {
                    if !searchText.isEmpty {
                        SearchViewMac(query: searchText)
                    } else {
                        DetailPlaceholder(selection: sidebarSelection, pendingArtistNavigation: $pendingArtistNavigation)
                    }
                }
                .navigationDestination(for: Album.self) { album in
                    AlbumDetailMac(album: album)
                        .contentHeader(backDestination)
                        .onAppear { rememberDetail("album:\(album.id.uuidString)") }
                }
                .navigationDestination(for: Artist.self) { artist in
                    ArtistDetailMac(artist: artist)
                        .contentHeader(backDestination)
                        .onAppear { rememberDetail("artist:\(artist.id.uuidString)") }
                }
                .navigationDestination(for: SearchAllRequest.self) { request in
                    SearchAllViewMac(request: request)
                        .contentHeader("Search")
                }
            }
        }
    }

    /// Split out from splitViewChrome purely so the type checker can finish.
    private var splitViewWithPlayer: some View {
        splitView
            // The toolbar carries the player, and SwiftUI's toolbar overflows well before
            // the space actually runs out: measured, everything survives at 1100 and the
            // filter drops under `»` by 1000. Below that it's the sidebar that has to
            // give, not the transport.
            .frame(minWidth: 900, minHeight: 600)
            .animation(.easeInOut(duration: 0.22), value: showQueue)
    }

    private var splitViewChrome: some View {
        splitViewWithPlayer
        .onReceive(NotificationCenter.default.publisher(for: .toggleUpNext)) { _ in
            guard NSApp.keyWindow?.identifier != MiniPlayerWindowController.windowIdentifier else { return }
            showQueue.toggle()
        }
        .replaceQueueConfirmation()
        .removeDownloadConfirmation()
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
            handleSelectionChange(newValue)
        }
        .onChange(of: detailPath.count) { _, depth in
            if depth == 0 { rememberDetail(nil) }
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
        .onAppear {
            if case .playlist(let id) = sidebarSelection, musicLibrary.playlist(id) == nil {
                sidebarSelection = .category(.artists)
            }
            restoreDetail()
            // Build the tracks cache before anyone opens Songs.
            Task { await musicLibrary.prepareAllTracks() }
            // Reopen the mini player if it was showing when the app last quit, in
            // whichever z-order and focus the user left the two windows in.
            if UserDefaults.standard.bool(forKey: MiniPlayerWindowController.visibleDefaultsKey) {
                let mp = miniPlayer ?? MiniPlayerWindowController(player: player, settings: settings, musicLibrary: musicLibrary, network: network)
                miniPlayer = mp
                mp.restoreAtLaunch()
                // Quit with only the mini player showing and that's what comes back. The
                // Window scene always creates its window regardless, so the delegate has
                // kept it off-screen since launch; now that the mini player is up it can
                // be closed for real.
                if MacOSAppDelegate.suppressesMainWindow {
                    MacOSAppDelegate.suppressesMainWindow = false
                    closeMainWindow()
                }
            }
        }
        .modifier(WindowNotificationHandlers(
            toggleMiniPlayer: toggleMiniPlayer,
            switchToMiniPlayer: switchToMiniPlayer,
            newPlaylist: { sidebarActions.createPlaylist(nil) },
            showActivity: { openWindow(id: "activity") },
            navigateToAlbum: { detailPath.append($0) },
            navigateToArtist: handleArtistNavigation,
            addToPlaylist: { addToPlaylistTrackIds = $0 }
        ))
    }

    /// Space toggles playback, but only when nothing is taking text input. A menu key
    /// equivalent can't make that distinction — it fires while the search field has
    /// focus — and a bare `.keyboardShortcut` never arrives at all once a list is first
    /// responder, because the list consumes the key first.
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

    static let lastSelectionKey = "MacOSLastSidebarSelection"

    private static func restoredSelection() -> SidebarSelection {
        guard let stored = UserDefaults.standard.string(forKey: lastSelectionKey),
              let selection = SidebarSelection(storageValue: stored)
        else { return .category(.artists) }
        return selection
    }

    private func handleArtistNavigation(_ artist: Artist) {
        if !searchText.isEmpty {
            // Push, so there's a way back to the results. Switching sections here clears
            // the search and strands you with nothing to return to.
            detailPath.append(artist)
            return
        }
        // Otherwise land in the Artists category on that artist. The
        // pendingArtistNavigation binding lets ArtistsViewMac skip its default
        // first-artist selection on first mount (no flicker).
        pendingArtistNavigation = artist.id
        sidebarSelection = .category(.artists)
    }

    static let lastDetailKey = "MacOSLastDetail"

    /// One level of drill-in, so relaunching lands back on the album or artist you had
    /// open rather than just the section it lives in. Deeper stacks aren't restored —
    /// they're rare, and NavigationPath doesn't round-trip our value types cleanly.
    private func rememberDetail(_ value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: Self.lastDetailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastDetailKey)
        }
    }

    private func restoreDetail() {
        guard searchText.isEmpty,
              let stored = UserDefaults.standard.string(forKey: Self.lastDetailKey)
        else { return }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return }
        switch parts[0] {
        case "album":
            if let album = musicLibrary.album(id) { detailPath.append(album) }
        case "artist":
            if let artist = musicLibrary.artist(id) { detailPath.append(artist) }
        default:
            break
        }
    }

    private func handleSelectionChange(_ newValue: SidebarSelection?) {
        if let newValue {
            UserDefaults.standard.set(newValue.storageValue, forKey: Self.lastSelectionKey)
        }
        // Switching sidebar items resets the drill-in stack so we don't show stale
        // album/artist detail under a new section.
        detailPath = NavigationPath()
        rememberDetail(nil)
        // Picking a section is a way out of search, the same as clearing the field.
        if newValue != nil, !searchText.isEmpty {
            searchText = ""
            selectionBeforeSearch = nil
        }
    }

    /// Everything except the mini player that can take main — the main window, whatever
    /// its title happens to be.
    private func closeMainWindow() {
        for window in NSApp.windows
        where window.identifier != MiniPlayerWindowController.windowIdentifier && window.canBecomeMain {
            window.close()
        }
    }

    /// Clicking the artwork swaps windows rather than stacking a second one on top,
    /// which is what Music.app does.
    private func switchToMiniPlayer() {
        let mp = miniPlayer ?? MiniPlayerWindowController(player: player, settings: settings, musicLibrary: musicLibrary, network: network)
        miniPlayer = mp
        mp.showWindow(nil)
        UserDefaults.standard.set(true, forKey: MiniPlayerWindowController.visibleDefaultsKey)
        closeMainWindow()
    }

    private func toggleMiniPlayer() {
        if let mp = miniPlayer {
            mp.toggle()
        } else {
            let mp = MiniPlayerWindowController(player: player, settings: settings, musicLibrary: musicLibrary, network: network)
            miniPlayer = mp
            mp.showWindow(nil)
            UserDefaults.standard.set(true, forKey: MiniPlayerWindowController.visibleDefaultsKey)
        }
    }

    static let queueWidth: CGFloat = 360
    /// How much content has to survive for the panel to push rather than float. Below
    /// this the column would be too narrow to be worth keeping visible.
    static let queuePushMinContent: CGFloat = 720

    /// The floating form of the queue panel, used when there isn't room to push.
    ///
    /// The transition goes on the panel itself, which is the view being inserted. Put it
    /// on a child of an inserted container instead and it never runs — the container
    /// takes SwiftUI's default opacity transition and the child comes in with it, which
    /// is why this faded at first.
    ///
    /// Deliberately not offset-and-clip: that keeps the panel laid out permanently, so
    /// every frame of the slide recomposites the whole overlay region over AppKit-hosted
    /// content that redraws on its own schedule, and the content tore mid-transition.
    private func queueOverlay(visible: Bool) -> some View {
        ZStack(alignment: .trailing) {
            // Always present, so nothing is inserted or removed behind the panel while
            // it moves; it only takes clicks while the panel is actually open.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { showQueue = false }
                .allowsHitTesting(visible)

            if visible {
                QueuePanel(isPresented: $showQueue)
                    .frame(width: Self.queueWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 0.5)
                    }
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
        a.downloadPlaylist = { playlistController.enableAutoDownload($0.id) }
        a.removePlaylistDownload = { [musicLibrary] playlist in
            let ids = Set(musicLibrary.tracksForPlaylist(playlist.id).filter(\.isDownloaded).map(\.id))
            DownloadRemovalRequest.post(trackIds: ids, subject: playlist.name, playlistId: playlist.id)
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
        a.addAlbumsToPlaylist = { albumIds, playlist in
            // Dropped in the order they were dragged, each album in its own track order.
            let trackIds = albumIds.flatMap { musicLibrary.tracksForAlbum($0).map(\.id) }
            guard !trackIds.isEmpty else { return }
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
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(NetworkMonitor.self) private var network
    @Environment(SettingsStore.self) private var settings
    @Binding var isPresented: Bool

    private var upNext: [(originalIndex: Int, item: QueueItem)] { player.upNextEntries }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                Spacer()
                if !upNext.isEmpty {
                    Button("Clear") { player.clearUpNext() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove everything after the current track")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: contentHeaderHeight)
            Divider()

            if upNext.isEmpty {
                ContentUnavailableView(
                    "Nothing Up Next",
                    systemImage: "list.bullet",
                    description: Text("Add tracks to the queue to see them here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                QueueTable(
                    items: upNext.map(\.item),
                    rowHeight: 52,
                    showsDuration: true,
                    accent: settings.resolvedAccentColor,
                    actions: .standard(player: player, musicLibrary: musicLibrary, network: network)
                )
            }
        }
        // The close button went, but Escape shouldn't have to go with it.
        .onExitCommand { isPresented = false }
    }
}

/// The window's notification wiring, lifted out of MacOSContentView.body — the modifier
/// chain there had grown past what the type checker will infer in reasonable time.
private struct WindowNotificationHandlers: ViewModifier {
    let toggleMiniPlayer: () -> Void
    let switchToMiniPlayer: () -> Void
    let newPlaylist: () -> Void
    let showActivity: () -> Void
    let navigateToAlbum: (Album) -> Void
    let navigateToArtist: (Artist) -> Void
    let addToPlaylist: ([UUID]) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newPlaylistRequested)) { _ in
                newPlaylist()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToMiniPlayer)) { _ in
                switchToMiniPlayer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
                toggleMiniPlayer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showDownloadActivity)) { _ in
                showActivity()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { note in
                guard let album = note.object as? Album else { return }
                navigateToAlbum(album)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { note in
                guard let artist = note.object as? Artist else { return }
                navigateToArtist(artist)
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestAddToPlaylist)) { note in
                guard let ids = note.object as? [UUID], !ids.isEmpty else { return }
                addToPlaylist(ids)
            }
    }
}
#endif
