import SwiftUI

struct FullPlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Artwork
                let artworkURL = player.queue.indices.contains(player.effectiveIndex)
                    ? player.queue[player.effectiveIndex].artworkURL : nil
                ArtworkView(url: artworkURL, cornerRadius: 12)
                    .frame(width: 300, height: 300)
                    .shadow(radius: 16, y: 8)

                // Track info
                VStack(spacing: 4) {
                    Text(player.currentTrack?.name ?? "")
                        .font(.title2.bold())
                        .lineLimit(1)
                    Text(player.currentTrack?.artist.name ?? "")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal)

                // Scrubber
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { isDragging ? dragValue : player.progress },
                            set: { newValue in
                                dragValue = newValue
                                isDragging = true
                            }
                        ),
                        in: 0...max(player.duration, 1),
                        onEditingChanged: { editing in
                            if !editing {
                                player.seek(to: dragValue)
                                isDragging = false
                            }
                        }
                    )

                    HStack {
                        Text(formatTime(isDragging ? dragValue : player.progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text("-" + formatTime(max(0, player.duration - (isDragging ? dragValue : player.progress))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal)

                // Controls
                HStack(spacing: 40) {
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.body)
                            .foregroundColor(player.isShuffled ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)

                    Button { player.back() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                    }
                    .buttonStyle(.plain)

                    Button { player.skip() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button { player.cycleRepeatMode() } label: {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.body)
                            .foregroundColor(player.repeatMode != .off ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }

                // Queue button
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .sheet(isPresented: $showQueue) {
                NavigationStack {
                    QueueView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showQueue = false }
                            }
                        }
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
