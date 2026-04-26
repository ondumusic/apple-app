import SwiftUI

/// Picker sheet shown via `.requestAddToPlaylist` notifications. Lists existing playlists and
/// offers an inline "New Playlist…" that creates and adds in one gesture. Accepts any number
/// of track ids, so the same sheet serves track/album/artist add-to-playlist flows.
struct AddToPlaylistSheet: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlaylistController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let trackIds: [UUID]

    @State private var entries: [PlaylistEntry] = []
    @State private var showCreateAndAdd = false

    private struct PlaylistEntry: Identifiable {
        let playlist: Playlist
        let folderPath: String?
        var id: UUID { playlist.id }
    }

    private var countLabel: String {
        "\(trackIds.count) \(trackIds.count == 1 ? "track" : "tracks")"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCreateAndAdd = true
                    } label: {
                        Label("New Playlist…", systemImage: "plus")
                    }
                }

                if !entries.isEmpty {
                    Section("Add \(countLabel) to") {
                        ForEach(entries) { entry in
                            Button {
                                controller.addTracks(trackIds, to: entry.playlist.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.playlist.name)
                                        if let folderPath = entry.folderPath {
                                            Text(folderPath)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text("\(entry.playlist.trackCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateAndAdd) {
                PlaylistNameSheet(mode: .create) { name in
                    if let created = controller.createPlaylist(name: name) {
                        controller.addTracks(trackIds, to: created.id)
                        dismiss()
                    }
                }
            }
            .onAppear { reload() }
            .onChange(of: musicLibrary.revision) { reload() }
        }
    }

    private func reload() {
        let all = musicLibrary.allPlaylists()
        let folderNames: [UUID: (name: String, parentId: UUID?)] = Dictionary(
            uniqueKeysWithValues: all
                .filter { $0.isFolder }
                .map { ($0.id, ($0.name, $0.parentId)) }
        )
        entries = all
            .filter { !$0.isFolder }
            .map { playlist in
                PlaylistEntry(
                    playlist: playlist,
                    folderPath: folderPath(for: playlist.parentId, folders: folderNames)
                )
            }
            .sorted { lhs, rhs in
                // Within a folder, alphabetical; across folders, group by path so siblings cluster.
                let lhsKey = (lhs.folderPath ?? "")
                let rhsKey = (rhs.folderPath ?? "")
                if lhsKey != rhsKey {
                    return lhsKey.localizedStandardCompare(rhsKey) == .orderedAscending
                }
                return lhs.playlist.name.localizedStandardCompare(rhs.playlist.name) == .orderedAscending
            }
    }

    /// Builds "Parent › Child" breadcrumb walking up the folder chain. Nil for root playlists.
    private func folderPath(for parentId: UUID?, folders: [UUID: (name: String, parentId: UUID?)]) -> String? {
        guard parentId != nil else { return nil }
        var names: [String] = []
        var visited: Set<UUID> = []
        var cursor = parentId
        while let id = cursor, visited.insert(id).inserted, let entry = folders[id] {
            names.append(entry.name)
            cursor = entry.parentId
        }
        guard !names.isEmpty else { return nil }
        return names.reversed().joined(separator: " › ")
    }
}
