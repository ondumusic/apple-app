import SwiftUI

struct PlaylistListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SyncService.self) private var syncService
    @Environment(PlaylistController.self) private var controller

    /// Nil at root, otherwise the folder being browsed.
    let parent: Playlist?

    @State private var entries: [Playlist] = []
    @State private var hasLoaded = false
    @State private var showCreatePlaylist = false
    @State private var showCreateFolder = false
    @State private var pendingDelete: Playlist?
    @State private var movingPlaylist: Playlist?
    @State private var renamingFolder: Playlist?

    init(parent: Playlist? = nil) {
        self.parent = parent
    }

    private var navigationTitle: String { parent?.name ?? "Playlists" }

    var body: some View {
        List {
            ForEach(entries) { entry in
                ZStack(alignment: .leading) {
                    NavigationLink(value: entry) { EmptyView() }
                        .opacity(0)
                    PlaylistRow(entry: entry, childCount: childCount(for: entry))
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .contextMenu {
                    if entry.isFolder {
                        FolderContextMenuItems(
                            onRename: { renamingFolder = entry },
                            onMove: { movingPlaylist = entry },
                            onDelete: { pendingDelete = entry }
                        )
                    } else {
                        PlaylistContextMenuItems(
                            playlist: entry,
                            onRequestMove: { movingPlaylist = entry },
                            onRequestDelete: { pendingDelete = entry }
                        )
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = entry
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await syncService.sync() }
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: Playlist.self) { entry in
            if entry.isFolder {
                PlaylistListView(parent: entry)
            } else {
                PlaylistDetailView(playlist: entry)
            }
        }
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showCreatePlaylist = true
                    } label: {
                        Label("New Playlist", systemImage: "music.note.list")
                    }
                    Button {
                        showCreateFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreatePlaylist) {
            PlaylistNameSheet(mode: .create) { name in
                controller.createPlaylist(name: name, parentId: parent?.id)
            }
        }
        .sheet(isPresented: $showCreateFolder) {
            PlaylistNameSheet(mode: .createFolder) { name in
                controller.createFolder(name: name, parentId: parent?.id)
            }
        }
        .sheet(item: $movingPlaylist) { entry in
            MovePlaylistSheet(playlist: entry)
        }
        .sheet(item: $renamingFolder) { folder in
            PlaylistNameSheet(mode: .rename(initialName: folder.name)) { name in
                controller.renamePlaylist(folder.id, name: name)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button(entry.isFolder ? "Delete Folder" : "Delete Playlist", role: .destructive) {
                controller.deletePlaylist(entry.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            if entry.isFolder {
                Text("This will permanently delete the folder and everything inside it.")
            } else {
                Text("This will permanently delete the playlist.")
            }
        }
        .overlay {
            if hasLoaded && entries.isEmpty {
                ContentUnavailableView(
                    parent == nil ? "No Playlists" : "Empty Folder",
                    systemImage: "music.note.list"
                )
            }
        }
        .task(id: musicLibrary.revision) {
            if hasLoaded {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            entries = musicLibrary.playlists(in: parent?.id)
            hasLoaded = true
        }
    }

    private var confirmationTitle: String {
        guard let pending = pendingDelete else { return "" }
        return "Delete \(pending.name)?"
    }

    private func childCount(for entry: Playlist) -> Int {
        guard entry.isFolder else { return 0 }
        return musicLibrary.childCount(of: entry.id)
    }
}

private struct PlaylistRow: View {
    let entry: Playlist
    let childCount: Int

    private var iconName: String {
        entry.isFolder ? "folder" : "music.note.list"
    }

    private var subtitle: String {
        if entry.isFolder {
            return "\(childCount) \(childCount == 1 ? "item" : "items")"
        }
        return "\(entry.trackCount) \(entry.trackCount == 1 ? "song" : "songs")"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct FolderContextMenuItems: View {
    let onRename: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        Button(action: onMove) {
            Label("Move…", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete Folder", systemImage: "trash")
        }
    }
}
