#if os(macOS)
import AppKit
import SwiftUI

/// NSPanel-backed mini player. Floating HUD-style window so it can stay above the main
/// window across spaces. Content is SwiftUI via NSHostingView.
@MainActor
final class MiniPlayerWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init(player: PlayerService) {
        let panel = MiniPlayerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
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

/// Custom NSPanel that can become key — needed so the user can close it with Cmd+W.
private final class MiniPlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
        VStack(spacing: 8) {
            if hovering || track == nil {
                transportRow
                    .transition(.opacity)
            }

            // Track info strip — always visible, sits at the bottom over a translucent
            // gradient so it stays readable on any artwork.
            VStack(spacing: 1) {
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
            }
            .padding(.bottom, 12)
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
#endif
