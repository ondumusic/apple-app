import SwiftUI

struct DownloadedAlbumDetailView: View {
    @Environment(PlayerService.self) private var player
    @Environment(OfflineStore.self) private var offlineStore
    @Environment(\.dismiss) private var dismiss

    let album: DownloadedAlbum
    @State private var showDeleteAlbumConfirmation = false
    @State private var trackToDelete: DownloadedTrack?

    private var sortedTracks: [DownloadedTrack] {
        album.tracks.sorted { ($0.disc, $0.number) < ($1.disc, $1.number) }
    }

    private var discs: [Int] {
        Array(Set(album.tracks.map(\.disc))).sorted()
    }

    private var hasMultipleDiscs: Bool { discs.count > 1 }

    private var queueItems: [QueueItem] {
        sortedTracks.map { downloaded in
            QueueItem(
                track: downloaded.asTrack,
                playbackURL: downloaded.localFileURL,
                artworkURL: album.artworkUrl
            )
        }
    }

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
                            HStack(spacing: 12) {
                                Button {
                                    player.playNow(queue: queueItems)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }

                                Button {
                                    player.playShuffled(queue: queueItems)
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
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
                    let discTracks = sortedTracks.filter { $0.disc == disc }
                    ForEach(discTracks) { track in
                        TrackRow(track: track.asTrack) {
                            if let index = sortedTracks.firstIndex(where: { $0.id == track.id }) {
                                player.playNow(queue: queueItems, startingAt: index)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                trackToDelete = track
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
                    showDeleteAlbumConfirmation = true
                } label: {
                    Label("Delete Album", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete Album",
            isPresented: $showDeleteAlbumConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                offlineStore.deleteAlbum(albumId: album.id)
                dismiss()
            }
        } message: {
            Text("Remove the downloaded album \"\(album.name)\"?")
        }
        .confirmationDialog(
            "Delete Track",
            isPresented: Binding(get: { trackToDelete != nil }, set: { if !$0 { trackToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let track = trackToDelete {
                    offlineStore.deleteTrack(trackId: track.id)
                }
            }
        } message: {
            if let track = trackToDelete {
                Text("Remove the downloaded track \"\(track.name)\"?")
            }
        }
    }

}
