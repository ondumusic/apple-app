#if os(macOS)
import SwiftUI

struct MacOSMiniPlayerView: View {
    @Environment(PlayerService.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showQueue = false

    private let size: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            if let track = player.currentTrack {
                let artworkURL = player.queue.indices.contains(player.effectiveIndex)
                    ? player.queue[player.effectiveIndex].artworkURL : nil

                // Full-width artwork
                ArtworkView(url: artworkURL, cornerRadius: 0)
                    .frame(width: size, height: size)
                    .clipped()

                // Scrubber
                GeometryReader { geo in
                    let displayProgress = isDragging ? dragValue : player.progress
                    let fraction = player.duration > 0 ? displayProgress / player.duration : 0

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.quaternary)
                        Rectangle()
                            .fill(.tint)
                            .frame(width: geo.size.width * min(fraction, 1))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let f = max(0, min(1, value.location.x / geo.size.width))
                                dragValue = f * player.duration
                            }
                            .onEnded { value in
                                let f = max(0, min(1, value.location.x / geo.size.width))
                                player.seek(to: f * player.duration)
                                isDragging = false
                            }
                    )
                }
                .frame(height: 3)

                // Track info + controls
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Text(track.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(track.artist.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 20) {
                        Button { player.back() } label: {
                            Image(systemName: "backward.fill")
                                .font(.body)
                        }
                        .buttonStyle(.plain)

                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        Button { player.skip() } label: {
                            Image(systemName: "forward.fill")
                                .font(.body)
                        }
                        .buttonStyle(.plain)

                        Button { showQueue.toggle() } label: {
                            Image(systemName: "list.bullet")
                                .font(.body)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showQueue) {
                            QueueView()
                                .frame(width: 280, height: 350)
                        }
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Not Playing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size)
        .ignoresSafeArea()
        .background(.ultraThinMaterial)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .containerBackground(.clear, for: .window)
    }
}
#endif
