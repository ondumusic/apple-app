#if os(macOS)
import SwiftUI
import AppKit

struct MacOSMiniPlayerView: View {
    @Environment(PlayerService.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private let size: CGFloat = 280

    private var track: Track? { player.currentTrack }

    private var artworkURL: URL? {
        player.queue.indices.contains(player.effectiveIndex)
            ? player.queue[player.effectiveIndex].artworkURL : nil
    }

    private var progressFraction: Double {
        guard player.duration > 0 else { return 0 }
        let value = isDragging ? dragValue : player.progress
        return min(value / player.duration, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Artwork
            ArtworkView(url: artworkURL, cornerRadius: 0)
                .frame(width: size, height: size)

            // Track info
            VStack(spacing: 2) {
                Text(track?.name ?? "")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(track?.artist.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                    Rectangle()
                        .fill(.tint)
                        .frame(width: geo.size.width * progressFraction)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(value.location.x / geo.size.width, 1))
                            dragValue = fraction * player.duration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(value.location.x / geo.size.width, 1))
                            player.seek(to: fraction * player.duration)
                            isDragging = false
                        }
                )
            }
            .frame(height: 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Controls
            HStack(spacing: 16) {
                Button { player.back() } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .disabled(!player.canGoBack)

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
                .disabled(!player.canSkip)
            }
            .padding(.bottom, 10)
        }
        .frame(width: size)
        .opacity(track != nil ? 1 : 0)
    }
}

// MARK: - NSPanel-based Mini Player Window

final class MiniPlayerPanel: NSPanel {
    init(player: PlayerService) {
        let panelSize = CGFloat(280)
        // artwork + info + progress + controls
        let height = panelSize + 40 + 16 + 40
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelSize, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        center()

        let hostingView = NSHostingView(
            rootView: MacOSMiniPlayerView()
                .environment(player)
        )
        contentView = hostingView
    }
}

@MainActor
enum MiniPlayerManager {
    private static var panel: MiniPlayerPanel?

    static func show(player: PlayerService) {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let newPanel = MiniPlayerPanel(player: player)
        newPanel.makeKeyAndOrderFront(nil)
        panel = newPanel
    }
}
#endif
