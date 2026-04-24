import SwiftUI

/// Picker sheet shown from track context menus. Lists existing playlists and offers an inline
/// "New Playlist..." that creates and adds the track in one gesture.
struct AddToPlaylistSheet: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlaylistController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let trackId: UUID

    @State private var playlists: [Playlist] = []
    @State private var showCreateAndAdd = false

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

                if !playlists.isEmpty {
                    Section("Add to") {
                        ForEach(playlists) { playlist in
                            Button {
                                Task {
                                    await controller.addTrack(trackId, to: playlist.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(.secondary)
                                    Text(playlist.name)
                                    Spacer()
                                    Text("\(playlist.trackCount)")
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
                    if let created = await controller.createPlaylist(name: name) {
                        await controller.addTrack(trackId, to: created.id)
                        dismiss()
                    }
                }
            }
            .onAppear {
                playlists = musicLibrary.allPlaylists()
            }
            .onChange(of: musicLibrary.revision) {
                playlists = musicLibrary.allPlaylists()
            }
        }
    }
}
