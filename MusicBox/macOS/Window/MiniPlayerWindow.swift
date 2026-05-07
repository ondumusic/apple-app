#if os(macOS)
import AppKit
import SwiftUI

/// NSPanel-backed mini player. SwiftUI's WindowGroup can't give us a HUD-style
/// always-on-top utility window, so we drop down to AppKit. The window's content is
/// still SwiftUI via NSHostingView.
@MainActor
final class MiniPlayerWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init(player: PlayerService) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 116),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 280, height: 100)

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

private struct MiniPlayerContent: View {
    @Environment(PlayerService.self) private var player

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? {
        guard player.queue.indices.contains(player.effectiveIndex) else { return nil }
        return player.queue[player.effectiveIndex].artworkURL
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if track != nil {
                    ArtworkView(url: artworkURL, cornerRadius: 4)
                        .frame(width: 56, height: 56)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.tertiary)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(track?.name ?? "Not Playing")
                        .font(.headline)
                        .lineLimit(1)
                    if let track {
                        Text(track.artist.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 14) {
                Button { player.back() } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(track == nil || !player.canGoBack)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .disabled(track == nil)

                Button { player.skip() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(track == nil || !player.canSkip)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
