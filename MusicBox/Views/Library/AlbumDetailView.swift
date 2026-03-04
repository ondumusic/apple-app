import SwiftUI

struct AlbumDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PlayerService.self) private var player

    let album: Album

    @State private var fullAlbum: Album?

    private var displayAlbum: Album { fullAlbum ?? album }
    private var tracks: [Track] { displayAlbum.tracks ?? [] }
    private var discs: [Int] { Array(Set(tracks.map(\.disc))).sorted() }
    private var hasMultipleDiscs: Bool { discs.count > 1 }

    var body: some View {
        List {
            // Album header
            Section {
                HStack(spacing: 16) {
                    ArtworkView(url: displayAlbum.artworkUrl)
                        .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayAlbum.name)
                            .font(.title2.bold())

                        if let year = displayAlbum.releaseYear {
                            Text(String(year))
                                .foregroundStyle(.secondary)
                        }

                        Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !tracks.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    player.playNow(tracks: tracks)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }

                                Button {
                                    player.playNow(tracks: tracks)
                                    if !player.isShuffled {
                                        player.toggleShuffle()
                                    }
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            // Tracks grouped by disc
            ForEach(discs, id: \.self) { disc in
                Section {
                    let discTracks = tracks.filter { $0.disc == disc }
                    ForEach(discTracks) { track in
                        TrackRow(track: track) {
                            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                                player.playNow(tracks: tracks, startingAt: index)
                            }
                        }
                    }
                } header: {
                    if hasMultipleDiscs {
                        Text("Disc \(disc)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(displayAlbum.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // Fetch full album to get tracks if not already included
            if album.tracks == nil || album.tracks?.isEmpty == true {
                await fetchAlbum()
            }
        }
    }

    private func fetchAlbum() async {
        guard let api = auth.apiService else { return }
        do {
            fullAlbum = try await api.fetchAlbum(album.id)
        } catch {}
    }
}
