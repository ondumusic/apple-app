import SwiftUI

struct DownloadedAlbumDetailView: View {
    @Environment(PlayerService.self) private var player
    @Environment(OfflineStore.self) private var offlineStore
    @Environment(\.dismiss) private var dismiss

    let album: DownloadedAlbum

    private var sortedTracks: [DownloadedTrack] {
        album.tracks.sorted { ($0.disc, $0.number) < ($1.disc, $1.number) }
    }

    private var discs: [Int] {
        Array(Set(album.tracks.map(\.disc))).sorted()
    }

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

                        Text("\(album.tracks.count) \(album.tracks.count == 1 ? "song" : "songs")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !sortedTracks.isEmpty {
                            Button {
                                playAll(startingAt: 0)
                            } label: {
                                Label("Play", systemImage: "play.fill")
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
                    let discTracks = sortedTracks.filter { $0.disc == disc }
                    ForEach(discTracks) { track in
                        HStack(spacing: 12) {
                            Text("\(track.number)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                                .monospacedDigit()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(track.formattedDuration)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let index = sortedTracks.firstIndex(where: { $0.id == track.id }) {
                                playAll(startingAt: index)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                offlineStore.deleteTrack(trackId: track.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                if let index = sortedTracks.firstIndex(where: { $0.id == track.id }) {
                                    playAll(startingAt: index)
                                }
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }

                            Button(role: .destructive) {
                                offlineStore.deleteTrack(trackId: track.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
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
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    offlineStore.deleteAlbum(albumId: album.id)
                    dismiss()
                } label: {
                    Label("Delete Album", systemImage: "trash")
                }
            }
        }
    }

    private func playAll(startingAt index: Int) {
        let queueItems = sortedTracks.map { downloaded -> QueueItem in
            let track = Track(
                id: downloaded.id,
                artistId: downloaded.artistId,
                albumArtistId: downloaded.artistId,
                albumId: downloaded.albumId,
                artist: Artist(id: downloaded.artistId, name: downloaded.artistName, sortName: downloaded.artistName, slug: ""),
                albumArtistSortName: downloaded.artistName,
                name: downloaded.name,
                disc: downloaded.disc,
                number: downloaded.number,
                duration: downloaded.duration,
                mimetype: downloaded.mimetype,
                streamUrl: ""
            )
            return QueueItem(
                track: track,
                playbackURL: downloaded.localFileURL,
                artworkURL: album.artworkUrl
            )
        }
        player.playNow(queue: queueItems, startingAt: index)
    }
}
