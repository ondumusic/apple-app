import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    let playlist: Playlist

    @State private var tracks: [Track] = []
    @State private var hasLoadedOnce: Bool = false

    private var hasPlayable: Bool {
        guard !tracks.isEmpty else { return false }
        if network.isOnline { return true }
        return tracks.contains { $0.isDownloaded }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(playlist.name)
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
                ForEach(tracks) { track in
                    TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                        if let index = available.firstIndex(where: { $0.id == track.id }) {
                            player.requestPlay { player.playNow(tracks: available, startingAt: index, artworkURL: track.album?.artworkUrl) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        tracks = musicLibrary.tracksForPlaylist(playlist.id)
        hasLoadedOnce = true
    }
}
