#if os(macOS)
import AppKit
import SwiftUI

/// NSPanel-backed mini player. Floating HUD-style window so it can stay above the main
/// window across spaces. Content is SwiftUI via NSHostingView.
@MainActor
final class MiniPlayerWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init(player: PlayerService) {
        // Plain resizable NSWindow (not a panel) so it behaves like any other window —
        // not always-on-top by default. Title bar hidden so the artwork can fill the
        // square content area; traffic lights overlay the top-left corner.
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 260),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Now Playing"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 220, height: 220)
        panel.aspectRatio = NSSize(width: 1, height: 1)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = MiniPlayerContent()
            .environment(player)
        hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        if let cv = panel.contentView {
            cv.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: cv.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
        }

        panel.center()
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if isVisible {
            close()
        } else {
            showWindow(nil)
        }
    }
}

/// Apple Music-style mini player. Square window dominated by the artwork; track info
/// overlays the bottom; transport controls fade in on hover.
private struct MiniPlayerContent: View {
    @Environment(PlayerService.self) private var player
    @State private var hovering = false

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? {
        guard player.queue.indices.contains(player.effectiveIndex) else { return nil }
        return player.queue[player.effectiveIndex].artworkURL
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork
            overlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var artwork: some View {
        if track != nil, let url = artworkURL {
            ArtworkView(url: url)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
        } else {
            // Empty state — subtle gradient, music note in center
            LinearGradient(
                colors: [.gray.opacity(0.35), .gray.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack(spacing: 6) {
            if hovering || track == nil {
                transportRow
                    .transition(.opacity)
            }

            // Track info strip — always visible, sits at the bottom over a translucent
            // gradient so it stays readable on any artwork.
            VStack(spacing: 2) {
                Text(track?.name ?? "Not Playing")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let track {
                    Text(track.artist.name)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                if track != nil, hovering {
                    MiniScrubber()
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.18), value: hovering)
    }

    private var transportRow: some View {
        HStack(spacing: 24) {
            Button { player.back() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(track == nil || !player.canGoBack)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(track == nil)

            Button { player.skip() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(track == nil || !player.canSkip)
        }
        .padding(.top, 12)
    }
}

private struct MiniScrubber: View {
    @Environment(PlayerService.self) private var player
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(format(isScrubbing ? scrubValue : player.progress))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : player.progress },
                    set: { newValue in
                        scrubValue = newValue
                        isScrubbing = true
                    }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: scrubValue)
                        isScrubbing = false
                    }
                }
            )
            .controlSize(.mini)
            .tint(.white)
            Text(format(player.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, alignment: .leading)
        }
    }

    private func format(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
