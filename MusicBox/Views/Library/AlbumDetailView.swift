import SwiftUI

struct AlbumDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network

    @Environment(\.dismiss) private var dismiss

    let album: Album
    var downloadedOnly: Bool = false

    @State private var tracks: [Track] = []
    @State private var totalTrackCount: Int = 0
    @State private var hasLoadedOnce: Bool = false

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

                        Group {
                            if downloadedOnly && tracks.count < totalTrackCount {
                                Text("\(tracks.count) of \(totalTrackCount) \(totalTrackCount == 1 ? "song" : "songs") downloaded")
                            } else {
                                Text("\(totalTrackCount) \(totalTrackCount == 1 ? "song" : "songs")")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !tracks.isEmpty {
                            let hasPlayable = network.isOnline || musicLibrary.downloadedTrackCount(albumId: album.id) > 0

                            HStack(spacing: 12) {
                                Button {
                                    let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                                    player.requestPlay { player.playNow(tracks: available, artworkURL: album.artworkUrl) }
                                } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 13))
                                        .frame(width: 18, height: 18)
                                }
                                .disabled(!hasPlayable)

                                Button {
                                    let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
                                    player.requestPlay { player.playShuffled(tracks: available, artworkURL: album.artworkUrl) }
                                } label: {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 13))
                                        .frame(width: 18, height: 18)
                                }
                                .disabled(!hasPlayable)

                                if downloadService.isAlbumDownloading(albumId: album.id) {
                                    Button {} label: {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(width: 18, height: 18)
                                    }
                                    .disabled(true)
                                } else if !musicLibrary.isAlbumFullyDownloaded(albumId: album.id) {
                                    Button {
                                        guard let fullAlbum = musicLibrary.albumWithTracks(album.id) else { return }
                                        let artist = musicLibrary.artist(album.artistId)
                                            ?? Artist(id: album.artistId, name: "", sortName: "", slug: "")
                                        downloadService.download(album: fullAlbum, artist: artist)
                                    } label: {
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 13))
                                            .frame(width: 18, height: 18)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.regular)
                            .offset(x: -4)
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
                                player.requestPlay { player.playNow(tracks: available, startingAt: index, artworkURL: album.artworkUrl) }
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
                    AlbumContextMenuItems(album: album, downloadedOnly: downloadedOnly)
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
            reloadTracks()
        }
        .onChange(of: musicLibrary.downloadChanged) {
            if downloadedOnly {
                reloadTracks()
            } else {
                musicLibrary.applyDownloadChanges(to: &tracks)
            }
        }
    }

    private func reloadTracks() {
        let allTracks = musicLibrary.tracksForAlbum(album.id)
        totalTrackCount = allTracks.count
        tracks = downloadedOnly
            ? allTracks.filter { $0.isDownloaded }
            : allTracks

        if downloadedOnly && hasLoadedOnce && tracks.isEmpty {
            dismiss()
        }
        hasLoadedOnce = true
    }
}
