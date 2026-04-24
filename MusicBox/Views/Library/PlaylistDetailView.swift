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
                            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                            player.requestPlay { player.playNow(tracks: available, artworkURL: nil) }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13))
                                .frame(width: 18, height: 18)
                        }
                        .disabled(!hasPlayable)

                        Button {
                            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                            player.requestPlay { player.playShuffled(tracks: available, artworkURL: nil) }
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
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                        if let startIndex = available.firstIndex(where: { $0.id == track.id }) {
                            player.requestPlay { player.playNow(tracks: available, startingAt: startIndex, artworkURL: track.album?.artworkUrl) }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if let item = items.indices.contains(index) ? items[index] : nil {
                            Button(role: .destructive) {
                                controller.removeItem(item.id, from: playlist.id)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(currentName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
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
