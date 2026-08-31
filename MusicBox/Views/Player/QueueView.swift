import SwiftUI

struct QueueView: View {
    @Environment(PlayerService.self) private var player
    @Environment(PlaylistController.self) private var controller

    @State private var showSaveAsPlaylist = false

    /// Tracks to persist as a new playlist: current track + everything queued after it, in play order.
    private var queueTracksForSaving: [Track] {
        guard !player.queue.isEmpty else { return [] }
        let count = player.queue.count
        var collected: [Track] = []
        if let current = player.currentTrack { collected.append(current) }
        for i in (player.currentIndex + 1)..<count {
            let effective: Int
            if let shuffled = player.shuffledIndices, i < shuffled.count {
                effective = shuffled[i]
            } else {
                effective = i
            }
            guard effective < player.queue.count else { continue }
            collected.append(player.queue[effective].track)
        }
        return collected
    }

    var body: some View {
        List {
            if let track = player.currentTrack {
                Section("Now Playing") {
                    queueRow(track: track, artworkURL: currentArtworkURL, isActive: true)
                }
            }

            let upNext = upNextItems
            if !upNext.isEmpty {
                Section("Up Next") {
                    ForEach(Array(upNext.enumerated()), id: \.element.id) { offset, item in
                        queueRow(track: item.track, artworkURL: item.artworkURL, isActive: false)
                            .onTapGesture {
                                player.skipTo(queueIndex: player.currentIndex + 1 + offset)
                            }
                    }
                    .onDelete { offsets in
                        player.removeFromQueue(at: offsets)
                    }
                    .onMove { source, destination in
                        Haptics.light()
                        player.moveQueueItems(from: source, to: destination)
                    }
                }
            }
        }
        .overlay {
            if player.queue.isEmpty {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "music.note.list",
                    description: Text("Pick something from your library to start listening.")
                )
            }
        }
        .navigationTitle("Queue")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showSaveAsPlaylist = true
                    } label: {
                        Label("Save as Playlist…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(queueTracksForSaving.isEmpty)

                    #if os(iOS)
                    if !upNextItems.isEmpty {
                        Button(role: .destructive) {
                            player.clearUpNext()
                        } label: {
                            Label("Clear Up Next", systemImage: "trash")
                        }
                    }
                    #endif
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSaveAsPlaylist) {
            PlaylistNameSheet(mode: .create) { name in
                let trackIds = queueTracksForSaving.map(\.id)
                if let playlist = controller.createPlaylist(name: name) {
                    controller.addTracks(trackIds, to: playlist.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                Button { player.toggleShuffle() } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(player.isShuffled ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { player.cycleRepeatMode() } label: {
                    Label(
                        player.repeatMode == .one ? "Repeat One" : "Repeat",
                        systemImage: player.repeatMode == .one ? "repeat.1" : "repeat"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(player.repeatMode != .off ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(.bar)
        }
    }

    private var currentArtworkURL: URL? {
        let idx = player.effectiveIndex
        guard player.queue.indices.contains(idx) else { return nil }
        return player.queue[idx].artworkURL
    }

    private var upNextItems: [QueueItem] { player.upNextEntries.map(\.item) }

    @ViewBuilder
    private func queueRow(track: Track, artworkURL: URL?, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: 4)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.callout)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                Text(track.artist.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
