import SwiftUI

struct QueueView: View {
    @Environment(PlayerService.self) private var player

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
                        player.moveQueueItems(from: source, to: destination)
                    }
                }
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
            #if os(iOS)
            if !upNextItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        player.clearUpNext()
                    }
                    .font(.subheadline)
                }
            }
            #endif
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
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var currentArtworkURL: URL? {
        let idx = player.effectiveIndex
        guard player.queue.indices.contains(idx) else { return nil }
        return player.queue[idx].artworkURL
    }

    private var upNextItems: [QueueItem] {
        guard !player.queue.isEmpty else { return [] }
        let count = player.queue.count
        var items: [QueueItem] = []
        for i in (player.currentIndex + 1)..<count {
            let effective: Int
            if let shuffled = player.shuffledIndices, i < shuffled.count {
                effective = shuffled[i]
            } else {
                effective = i
            }
            guard effective < player.queue.count else { continue }
            items.append(player.queue[effective])
        }
        return items
    }

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
