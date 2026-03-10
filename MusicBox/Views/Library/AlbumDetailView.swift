import SwiftUI

struct AlbumDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network

    let album: Album

    @State private var showRemoveDownloadConfirmation = false
    @State private var tracks: [Track] = []

    private var discs: [Int] { Array(Set(tracks.map(\.disc))).sorted() }
    private var hasMultipleDiscs: Bool { discs.count > 1 }

    var body: some View {
        List {
            // Album header
            Section {
                HStack(spacing: 16) {
                    ArtworkView(url: album.artworkUrl)
                        .frame(width: 120, height: 120)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.name)
                            .font(.title2.bold())

                        if let year = album.releaseYear {
                            Text(String(year))
                                .foregroundStyle(.secondary)
                        }

                        Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !tracks.isEmpty {
                            let hasPlayable = network.isOnline || musicLibrary.downloadedTrackCount(albumId: album.id) > 0

                            HStack(spacing: 12) {
                                Button {
                                    let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                                    player.playNow(tracks: available, artworkURL: album.artworkUrl)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .disabled(!hasPlayable)

                                Button {
                                    let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                                    player.playShuffled(tracks: available, artworkURL: album.artworkUrl)
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                                .disabled(!hasPlayable)

                                if downloadService.isAlbumDownloading(albumId: album.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if musicLibrary.downloadedTrackCount(albumId: album.id) == tracks.count && !tracks.isEmpty {
                                    Button {
                                        showRemoveDownloadConfirmation = true
                                    } label: {
                                        Label("Remove", systemImage: "arrow.down.circle.fill")
                                    }
                                    .confirmationDialog(
                                        "Remove Download",
                                        isPresented: $showRemoveDownloadConfirmation,
                                        titleVisibility: .visible
                                    ) {
                                        Button("Remove", role: .destructive) {
                                            musicLibrary.markAlbumUndownloaded(albumId: album.id)
                                        }
                                    } message: {
                                        Text("Remove the downloaded album \"\(album.name)\"?")
                                    }
                                } else {
                                    Button {
                                        let artist = musicLibrary.artist(album.artistId)
                                            ?? Artist(id: album.artistId, name: "", sortName: "", slug: "")
                                        let fullAlbum = Album(
                                            id: album.id, artistId: album.artistId,
                                            name: album.name, sortName: album.sortName,
                                            slug: album.slug, releaseYear: album.releaseYear,
                                            tracks: tracks, isUnknown: album.isUnknown,
                                            artworkUrl: album.artworkUrl)
                                        downloadService.download(album: fullAlbum, artist: artist)
                                    } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                            }
                            .labelStyle(.iconOnly)
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
                        TrackRow(track: track, album: album) {
                            let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                            if let index = available.firstIndex(where: { $0.id == track.id }) {
                                player.playNow(tracks: available, startingAt: index, artworkURL: album.artworkUrl)
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
        .navigationTitle(album.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    AlbumContextMenuItems(album: album)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView("No Tracks", systemImage: "music.note")
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) {
            tracks = musicLibrary.tracksForAlbum(album.id)
        }
    }
}
