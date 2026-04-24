import SwiftUI

/// Picker sheet shown via `.requestAddToPlaylist` notifications. Lists existing playlists and
/// offers an inline "New Playlist…" that creates and adds in one gesture. Accepts any number
/// of track ids, so the same sheet serves track/album/artist add-to-playlist flows.
struct AddToPlaylistSheet: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlaylistController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let trackIds: [UUID]

    @State private var playlists: [Playlist] = []
    @State private var showCreateAndAdd = false

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

                if !playlists.isEmpty {
                    Section("Add \(countLabel) to") {
                        ForEach(playlists) { playlist in
                            Button {
                                controller.addTracks(trackIds, to: playlist.id)
                                dismiss()
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
                    if let created = controller.createPlaylist(name: name) {
                        controller.addTracks(trackIds, to: created.id)
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
