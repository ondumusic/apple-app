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
                        DetailPlaceholder(selection: sidebarSelection)
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
        .queueConfirmationOverlay()
        .replaceQueueConfirmation()
        .toolbar(removing: .sidebarToggle)
        .toolbar { PlayerToolbar(showQueue: $showQueue) }
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(isPresented: $showQueue) {
            QueueSheet(isPresented: $showQueue)
        }
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
            // Switch to the Artists category. ArtistsViewMac listens for the same
            // notification and updates its master selection to the requested artist —
            // we don't push onto the detail stack because the master/detail split
            // is the canonical home for artists.
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

    var body: some View {
        switch selection {
        case .category(.songs):
            SongsViewMac()
        case .category(.albums):
            AlbumsViewMac()
        case .category(.artists):
            ArtistsViewMac()
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

private struct QueueSheet: View {
    @Environment(PlayerService.self) private var player
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            if index == player.effectiveIndex {
                                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                    .foregroundStyle(.tint)
                                    .frame(width: 16)
                            } else {
                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
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
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            player.requestPlay {
                                player.playNow(queue: player.queue, startingAt: index)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 460, height: 540)
    }
}
#endif
