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
                                let targetIndex: Int
                                if let shuffled = player.shuffledIndices {
                                    // Find the position in the shuffled order
                                    targetIndex = player.currentIndex + 1 + offset
                                } else {
                                    targetIndex = player.currentIndex + 1 + offset
                                }
                                player.skipTo(queueIndex: targetIndex)
                            }
                    }
                }
            }
        }
        .navigationTitle("Queue")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
