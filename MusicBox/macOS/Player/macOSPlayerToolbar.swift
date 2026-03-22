import SwiftUI

struct MacOSPlayerToolbar: View {
    @Environment(PlayerService.self) private var player
    @State private var showQueue = false

    private var track: Track? { player.currentTrack }

    private var artworkURL: URL? {
        player.queue.indices.contains(player.effectiveIndex)
            ? player.queue[player.effectiveIndex].artworkURL : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: 4)
                .frame(width: 28, height: 28)
                .onTapGesture { MiniPlayerManager.show(player: player) }

            VStack(alignment: .leading, spacing: 1) {
                Text(track?.name ?? "")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(track?.artist.name ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 160, alignment: .leading)

            HStack(spacing: 8) {
                Button { player.back() } label: {
                    Image(systemName: "backward.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(!player.canGoBack)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)

                Button { player.skip() } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(!player.canSkip)
            }

            Button { showQueue.toggle() } label: {
                Image(systemName: "list.bullet")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showQueue) {
                QueueView()
                    .frame(width: 300, height: 400)
            }

            Button { MiniPlayerManager.show(player: player) } label: {
                Image(systemName: "pip")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Open Mini Player")
        }
        .opacity(track != nil ? 1 : 0)
        .allowsHitTesting(track != nil)
    }
}
