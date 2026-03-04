import SwiftUI

struct MacOSPlayerToolbar: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.openWindow) private var openWindow
    @State private var showQueue = false

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                let artworkURL = player.queue.indices.contains(player.effectiveIndex)
                    ? player.queue[player.effectiveIndex].artworkURL : nil

                ArtworkView(url: artworkURL, cornerRadius: 4)
                    .frame(width: 28, height: 28)
                    .onTapGesture { openWindow(id: "mini-player") }

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(track.artist.name)
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

                Button { openWindow(id: "mini-player") } label: {
                    Image(systemName: "pip")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Open Mini Player")
            }
        }
    }
}
