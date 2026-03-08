import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerService.self) private var player
    var onTap: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                Divider()

                // Progress bar
                GeometryReader { geo in
                    let fraction = player.duration > 0 ? player.progress / player.duration : 0
                    Rectangle()
                        .fill(.tint)
                        .frame(width: geo.size.width * min(fraction, 1))
                }
                .frame(height: 2)
                .background(.quaternary)

                HStack(spacing: 12) {
                    let artworkURL = player.queue.indices.contains(player.effectiveIndex)
                        ? player.queue[player.effectiveIndex].artworkURL : nil

                    ArtworkView(url: artworkURL, cornerRadius: 6)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(track.artist.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { player.skip() } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.canSkip)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
            }
            .background(.ultraThinMaterial)
        }
    }
}
