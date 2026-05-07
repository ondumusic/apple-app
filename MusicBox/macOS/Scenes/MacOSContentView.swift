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

    @State private var showQueue = false
    @State private var sidebarSelection: SidebarSelection? = .category(.artists)
    @State private var detailPath = NavigationPath()
    @State private var renameTarget: Playlist?
    @State private var deleteTarget: Playlist?
    @State private var pendingCreate: PendingCreate?
    @State private var searchText: String = ""
    @State private var miniPlayer: MiniPlayerWindowController?

    private struct PendingCreate: Identifiable {
        let id = UUID()
        let parentId: UUID?
        let isFolder: Bool
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(
                selection: $sidebarSelection,
                searchText: $searchText,
                musicLibrary: musicLibrary,
                actions: sidebarActions
            )
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
        .toolbar { PlayerToolbar(showQueue: $showQueue) }
        .sheet(isPresented: $showQueue) {
            QueueSheetPlaceholder(isPresented: $showQueue)
        }
        .sheet(item: $renameTarget) { playlist in
            PlaylistNameSheet(mode: .rename(initialName: playlist.name)) { newName in
                playlistController.renamePlaylist(playlist.id, name: newName)
            }
        }
        .sheet(item: $pendingCreate) { pending in
            PlaylistNameSheet(mode: pending.isFolder ? .createFolder : .create) { name in
                if pending.isFolder {
                    playlistController.createFolder(name: name, parentId: pending.parentId)
                } else {
                    playlistController.createPlaylist(name: name, parentId: pending.parentId)
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayer)) { _ in
            toggleMiniPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            detailPath.append(album)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            sidebarSelection = .category(.artists)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                detailPath.append(artist)
            }
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
        a.renamePlaylist = { playlist in
            renameTarget = playlist
        }
        a.deletePlaylist = { playlist in
            deleteTarget = playlist
        }
        a.addTracksToPlaylist = { trackIds, playlist in
            playlistController.addTracks(trackIds, to: playlist.id)
        }
        a.createPlaylist = { parentId in
            pendingCreate = PendingCreate(parentId: parentId, isFolder: false)
        }
        a.createFolder = { parentId in
            pendingCreate = PendingCreate(parentId: parentId, isFolder: true)
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

private struct QueueSheetPlaceholder: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Queue")
                .font(.headline)
            Text("QueueView will be re-wired to NSTableView in the tracks step.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 320, height: 200)
    }
}
#endif
