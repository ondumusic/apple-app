import SwiftUI

struct PlaylistListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SyncService.self) private var syncService
    @Environment(PlaylistController.self) private var controller

    @State private var playlists: [Playlist] = []
    @State private var hasLoaded = false
    @State private var showCreate = false
    @State private var pendingDelete: Playlist?

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                ZStack(alignment: .leading) {
                    NavigationLink(value: playlist) { EmptyView() }
                        .opacity(0)
                    PlaylistRow(playlist: playlist)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = playlist
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await syncService.sync() }
        .navigationTitle("Playlists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistDetailView(playlist: playlist)
        }
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            PlaylistNameSheet(mode: .create) { name in
                controller.createPlaylist(name: name)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "playlist")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { playlist in
            Button("Delete Playlist", role: .destructive) {
                controller.deletePlaylist(playlist.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This will permanently delete the playlist.")
        }
        .overlay {
            if hasLoaded && playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
            }
        }
        .task(id: musicLibrary.revision) {
            if hasLoaded {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            playlists = musicLibrary.allPlaylists()
            hasLoaded = true
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("\(playlist.trackCount) \(playlist.trackCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
