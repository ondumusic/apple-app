#if os(macOS)
import SwiftUI

/// Player content for the macOS window toolbar. Built as a set of ToolbarContent items
/// rather than one principal item — putting a complex interactive view (incl. a popover)
/// inside a single ToolbarItem.principal caused beachball/hang in earlier iterations.
struct PlayerToolbar: ToolbarContent {
    @Environment(PlayerService.self) private var player
    @Binding var showQueue: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ShuffleButton()
            TransportButtons()
            RepeatButton()
        }
        ToolbarItem(placement: .principal) {
            NowPlayingLabel()
                .frame(minWidth: 260, idealWidth: 420, maxWidth: 460)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            VolumeControl()

            Button {
                showQueue.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(showQueue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .help("Queue")
            .accessibilityLabel("Queue")
            .disabled(player.currentTrack == nil)
        }
    }

}

private struct ShuffleButton: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        Button { player.toggleShuffle() } label: {
            Image(systemName: "shuffle")
                .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .help(player.isShuffled ? "Disable Shuffle" : "Shuffle")
        .accessibilityLabel("Shuffle")
        .accessibilityValue(player.isShuffled ? "On" : "Off")
        .disabled(player.queue.isEmpty)
    }
}

private struct RepeatButton: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        Button { player.cycleRepeatMode() } label: {
            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                .foregroundStyle(player.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .help(help)
        .accessibilityLabel("Repeat")
        .accessibilityValue(help)
        .disabled(player.queue.isEmpty)
    }

    private var help: String {
        switch player.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
        }
    }
}

private struct TransportButtons: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 4) {
            Button { player.back() } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!player.canGoBack || player.currentTrack == nil)
            .help("Previous")
            .accessibilityLabel("Previous")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(player.currentTrack == nil)
            .help(player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.skip() } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.canSkip || player.currentTrack == nil)
            .help("Next")
            .accessibilityLabel("Next")
        }
    }
}

private struct NowPlayingLabel: View {
    @Environment(PlayerService.self) private var player

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? {
        guard player.queue.indices.contains(player.effectiveIndex) else { return nil }
        return player.queue[player.effectiveIndex].artworkURL
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                artwork
                // Title and artist on their own lines, the way Music.app's display reads.
                // One line with a dash crammed everything against the top edge.
                VStack(spacing: 1) {
                    if let error = player.playbackError {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .help(error)
                        }
                    } else {
                        HStack(spacing: 5) {
                            if player.isBuffering {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.55)
                                    .frame(width: 12, height: 12)
                            }
                            Text(track?.name ?? "Not Playing")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        Text(track?.artist.name ?? " ")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if track != nil {
                        ScrubberView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            // Shorter than the 52pt toolbar so it sits inside it with a margin, rather
            // than filling it edge to edge and spilling into the content below.
            .frame(height: 42)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if track != nil {
                ArtworkView(url: artworkURL, cornerRadius: 3)
                    .frame(width: 30, height: 30)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tertiary)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
        }
        .help("Open Mini Player")
    }
}

private struct VolumeControl: View {
    @Environment(PlayerService.self) private var player
    @State private var showingSlider = false

    var body: some View {
        @Bindable var player = player
        Button { showingSlider.toggle() } label: {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
        }
        .help("Volume")
        .accessibilityLabel("Volume")
        .popover(isPresented: $showingSlider, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 130)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var iconName: String {
        switch player.volume {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.fill"
        case ..<0.67: "speaker.wave.1.fill"
        default: "speaker.wave.2.fill"
        }
    }
}

private struct ScrubberView: View {
    @Environment(PlayerService.self) private var player
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(format(isScrubbing ? scrubValue : player.progress))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressTrack(
                value: isScrubbing ? scrubValue : player.progress,
                duration: max(player.duration, 1),
                onScrub: { value in
                    scrubValue = value
                    isScrubbing = true
                },
                onCommit: {
                    player.seek(to: scrubValue)
                    isScrubbing = false
                }
            )
            .frame(height: 8)
            Text(format(player.duration))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Thin progress track. SwiftUI gesture leaks through to the window's
/// "isMovableByWindowBackground" drag in the toolbar, so the pointer interaction
/// is handled in an NSView wrapper that owns the mouseDown/Up events explicitly.
struct ProgressTrack: View {
    let value: Double
    let duration: Double
    let onScrub: (Double) -> Void
    let onCommit: () -> Void
    var tint: Color = .accentColor
    var trackColor: Color = Color.primary.opacity(0.18)

    var body: some View {
        ProgressTrackRepresentable(
            value: value,
            duration: duration,
            tint: NSColor(tint),
            trackColor: NSColor(trackColor),
            onScrub: onScrub,
            onCommit: onCommit
        )
    }
}

private struct ProgressTrackRepresentable: NSViewRepresentable {
    let value: Double
    let duration: Double
    let tint: NSColor
    let trackColor: NSColor
    let onScrub: (Double) -> Void
    let onCommit: () -> Void

    func makeNSView(context: Context) -> ProgressTrackNSView {
        ProgressTrackNSView()
    }

    func updateNSView(_ nsView: ProgressTrackNSView, context: Context) {
        nsView.value = value
        nsView.duration = duration
        nsView.tint = tint
        nsView.trackColor = trackColor
        nsView.onScrub = onScrub
        nsView.onCommit = onCommit
        nsView.needsDisplay = true
    }
}

final class ProgressTrackNSView: NSView {
    var value: Double = 0
    var duration: Double = 1
    var tint: NSColor = .controlAccentColor
    var trackColor: NSColor = NSColor.labelColor.withAlphaComponent(0.18)
    var onScrub: (Double) -> Void = { _ in }
    var onCommit: () -> Void = { }

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override var wantsUpdateLayer: Bool { false }
    /// Returning true here — combined with mouseDown/dragged/up — prevents the toolbar's
    /// window-drag gesture from intercepting our clicks.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        scrub(to: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseDragged(with event: NSEvent) {
        scrub(to: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        onCommit()
    }

    private func scrub(to x: CGFloat) {
        guard bounds.width > 0 else { return }
        let clamped = min(max(x, 0), bounds.width)
        let frac = clamped / bounds.width
        onScrub(Double(frac) * duration)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackHeight: CGFloat = isHovered ? 4 : 2
        let centerY = bounds.midY
        let trackRect = NSRect(x: 0, y: centerY - trackHeight / 2, width: bounds.width, height: trackHeight)
        let radius = trackHeight / 2
        let path = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        trackColor.setFill()
        path.fill()

        let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0
        let fillWidth = bounds.width * CGFloat(fraction)
        guard fillWidth > 0 else { return }
        let fillRect = NSRect(x: 0, y: centerY - trackHeight / 2, width: fillWidth, height: trackHeight)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        tint.setFill()
        fillPath.fill()
    }
}
#endif
