import SwiftUI

/// Picker for moving a playlist or folder into another folder (or back to root).
/// Excludes the moving entry itself and any of its descendants — those would be invalid
/// destinations (would create a cycle for folders).
struct MovePlaylistSheet: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlaylistController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist

    @State private var folders: [FolderNode] = []

    private struct FolderNode: Identifiable, Hashable {
        let id: UUID
        let name: String
        let depth: Int
    }

    private var titleText: String {
        playlist.isFolder ? "Move Folder" : "Move Playlist"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Destination") {
                    if playlist.parentId != nil {
                        Button {
                            controller.movePlaylist(playlist.id, to: nil)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "tray")
                                    .foregroundStyle(.secondary)
                                Text("Playlists (Root)")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(folders) { folder in
                        let isCurrent = folder.id == playlist.parentId
                        Button {
                            guard !isCurrent else { return }
                            controller.movePlaylist(playlist.id, to: folder.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, CGFloat(folder.depth) * 12)
                                Text(folder.name)
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCurrent)
                    }
                }
            }
            .navigationTitle(titleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadFolders() }
        }
    }

    private func loadFolders() {
        let excluded: Set<UUID> = playlist.isFolder
            ? Set(musicLibrary.descendantIds(of: playlist.id))
            : [playlist.id]
        folders = flattenFolders(parentId: nil, depth: 0, excluded: excluded)
    }

    private func flattenFolders(parentId: UUID?, depth: Int, excluded: Set<UUID>) -> [FolderNode] {
        let children = musicLibrary.playlists(in: parentId)
            .filter { $0.isFolder && !excluded.contains($0.id) }
        var result: [FolderNode] = []
        for child in children {
            result.append(FolderNode(id: child.id, name: child.name, depth: depth))
            result.append(contentsOf: flattenFolders(parentId: child.id, depth: depth + 1, excluded: excluded))
        }
        return result
    }
}
