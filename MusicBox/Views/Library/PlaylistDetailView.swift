import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(PlaylistController.self) private var controller
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist

    @State private var tracks: [Track] = []
    @State private var items: [PlaylistItem] = []
    @State private var currentName: String
    @State private var hasLoadedOnce: Bool = false
    @State private var showRename = false
    @State private var showDeleteConfirm = false

    init(playlist: Playlist) {
        self.playlist = playlist
        self._currentName = State(initialValue: playlist.name)
    }

    private var hasPlayable: Bool {
        guard !tracks.isEmpty else { return false }
        if network.isOnline { return true }
        return tracks.contains { $0.isDownloaded }
    }

    /// Queue items built with each playlist item's id as the `QueueItem.id`. This lets us tell
    /// "the third occurrence of track A" apart from "the fifth occurrence" when highlighting
    /// the currently-playing row.
    private func buildQueueItems() -> [QueueItem] {
        zip(items, tracks).map { item, track in
            QueueItem(id: item.id, track: track, artworkURL: track.album?.artworkUrl)
        }
    }

    /// Returns the subset of queue items that are currently playable (online or downloaded).
    private func availableQueueItems() -> [QueueItem] {
        buildQueueItems().filter { network.isOnline || $0.track.isDownloaded }
    }

    private func isItemPlaying(_ item: PlaylistItem) -> Bool {
        guard player.queue.indices.contains(player.effectiveIndex) else { return false }
        return player.queue[player.effectiveIndex].id == item.id
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentName)
                        .font(.title2.bold())

                    Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
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
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .offset(x: -4)
                    .padding(.top, 4)
                }
                .listRowSeparator(.hidden)
            }

            Section {
                // Iterate items (unique ids) rather than tracks (which can duplicate when the same
                // track appears multiple times in the playlist).
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let track = tracks[index]
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
                .onMove(perform: handleMove)
            }
        }
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
        }
    }

    private func handleMove(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first, items.indices.contains(sourceIndex) else { return }
        let movingItem = items[sourceIndex]

        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = reordered.firstIndex(where: { $0.id == movingItem.id }) else { return }

        let before = newIndex > 0 ? reordered[newIndex - 1].position : nil
        let after  = newIndex < reordered.count - 1 ? reordered[newIndex + 1].position : nil
        let newPosition = FractionalIndex.between(before, after)

        controller.moveItem(movingItem.id, to: newPosition, within: playlist.id)
    }

    private func reloadTracks() {
        items = musicLibrary.playlistItems(playlist.id)
        let allTracks = musicLibrary.tracksForPlaylist(playlist.id)
        // tracksForPlaylist skips missing-from-library items, so filter `items` to match.
        let trackIds = Set(allTracks.map(\.id))
        items = items.filter { trackIds.contains($0.trackId) }
        tracks = allTracks
        hasLoadedOnce = true

        // Also refresh the display name in case sync applied a rename.
        if let refreshed = musicLibrary.playlist(playlist.id) {
            currentName = refreshed.name
        }
    }
}
