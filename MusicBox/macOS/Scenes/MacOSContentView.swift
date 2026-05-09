#if os(macOS)
import SwiftUI

/// Root macOS content view. SwiftUI shell that hosts the AppKit-backed sidebar,
/// track tables, toolbar, and mini-player. Layout fills in piece by piece — see
/// project_macos_rebuild_plan.md for the per-surface plan.
struct MacOSContentView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
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
    @State private var searchText: String = ""
    @State private var miniPlayer: MiniPlayerWindowController?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            Sidebar(
                selection: $sidebarSelection,
                searchText: $searchText,
                musicLibrary: musicLibrary,
                actions: sidebarActions,
                downloadingCount: downloadService.activeDownloads.count + downloadService.pendingQueue.count
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
                    AlbumDetailMac(album: album)
                }
                .navigationDestination(for: Artist.self) { artist in
                    ArtistDetailMac(artist: artist)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay(alignment: .trailing) {
            // Slide-over queue panel — overlays detail content from the right edge,
            // doesn't push other content away. Click outside or the close button to
            // dismiss.
            if showQueue {
                ZStack(alignment: .trailing) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { showQueue = false }
                    QueuePanel(isPresented: $showQueue)
                        .frame(width: 360)
                        .background(Color(NSColor.windowBackgroundColor))
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: -2, y: 0)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showQueue)
        .queueConfirmationOverlay()
        .replaceQueueConfirmation()
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
        .onChange(of: sidebarSelection) {
            // Switching sidebar items resets the drill-in stack so we don't show stale
            // album/artist detail under a new section.
            detailPath = NavigationPath()
        }
        .onChange(of: sidebarVisibility) { _, newValue in
            // We don't allow the sidebar to be hidden — clamp back to .all if anything
            // (toolbar button, View menu, keyboard shortcut) tries to collapse it.
            if newValue != .all {
                sidebarVisibility = .all
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
            toggleMiniPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
            player.togglePlayPause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            detailPath.append(album)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            // Switch to the Artists category and record which artist to land on. The
            // pendingArtistNavigation binding lets ArtistsViewMac skip its default
            // first-artist selection on first mount (no flicker).
            if let artist = notification.object as? Artist {
                pendingArtistNavigation = artist.id
            }
            sidebarSelection = .category(.artists)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestAddToPlaylist)) { notification in
            guard let ids = notification.object as? [UUID], !ids.isEmpty else { return }
            addToPlaylistTrackIds = ids
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

    private func toggleMiniPlayer() {
        if let mp = miniPlayer {
            mp.toggle()
        } else {
            let mp = MiniPlayerWindowController(player: player)
            miniPlayer = mp
            mp.showWindow(nil)
        }
    }

    private var sidebarActions: SidebarActions {
        var a = SidebarActions()
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
            DownloadsView()
        case .playlist(let id):
            PlaylistDetailMac(playlistId: id)
                .id(id)
        case .none:
            ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
        }
    }
}

/// Slide-over queue panel — anchored to the right edge of the window, overlays
/// detail content (no push). Editable: drag to reorder, swipe to remove.
struct QueuePanel: View {
    @Environment(PlayerService.self) private var player
    @Binding var isPresented: Bool

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
            if player.queue.isEmpty {
                ContentUnavailableView(
                    "Queue Empty",
                    systemImage: "list.bullet",
                    description: Text("Play something to populate the queue.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                        QueuePanelRow(index: index, item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    player.removeFromQueue(at: IndexSet(integer: index))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button("Play") {
                                    player.requestPlay {
                                        player.playNow(queue: player.queue, startingAt: index)
                                    }
                                }
                                Button(role: .destructive) {
                                    player.removeFromQueue(at: IndexSet(integer: index))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    .onMove { source, destination in
                        player.moveQueueItems(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// One row in the queue panel — extracted so the row hit-testing for double-click
/// doesn't conflict with List's swipe / drag gestures.
private struct QueuePanelRow: View {
    @Environment(PlayerService.self) private var player
    let index: Int
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            if index == player.effectiveIndex {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 16)
            } else {
                Text("\(index + 1)")
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.track.name).lineLimit(1)
                Text(item.track.artist.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.track.formattedDuration)
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            player.requestPlay {
                player.playNow(queue: player.queue, startingAt: index)
            }
        }
    }
}
#endif
