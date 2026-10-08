#if os(macOS)
import SwiftUI

/// The player's individual controls, shared by the window's player row and the mini
/// player.
struct ShuffleButton: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        Button { player.toggleShuffle() } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 14))
                .frame(width: playerControlSize, height: playerControlSize)
                .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .help(player.isShuffled ? "Disable Shuffle" : "Shuffle")
        .accessibilityLabel("Shuffle")
        .accessibilityValue(player.isShuffled ? "On" : "Off")
        .disabled(player.queue.isEmpty)
    }
}

struct RepeatButton: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        Button { player.cycleRepeatMode() } label: {
            Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.system(size: 14))
                .frame(width: playerControlSize, height: playerControlSize)
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

/// Every control in the player row shares this frame. Measured in Music.app: shuffle,
/// previous, play, next and repeat are all 34x34, butted edge to edge.
let playerControlSize: CGFloat = 34

struct TransportButtons: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            Button { player.back() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
                    .frame(width: playerControlSize, height: playerControlSize)
            }
            .disabled(!player.canGoBack || player.currentTrack == nil)
            .help("Previous")
            .accessibilityLabel("Previous")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19))
                    .frame(width: playerControlSize, height: playerControlSize)
            }
            .disabled(player.currentTrack == nil)
            .help(player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.skip() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
                    .frame(width: playerControlSize, height: playerControlSize)
            }
            .disabled(!player.canSkip || player.currentTrack == nil)
            .help("Next")
            .accessibilityLabel("Next")
        }
    }
}

struct NowPlayingLabel: View {
    @Environment(PlayerService.self) private var player

    private var track: Track? { player.currentTrack }
    @State private var isHoveringArtwork = false

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
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            // Light rather than grey, with the artwork flush to the leading edge — that's
            // what Music's LCD does, and the grey fill was most of why ours read as a
            // different kind of object. Shallow inset: the lip along the bottom sells the
            // recess, so the shadow only has to hint.
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        Color(nsColor: .textBackgroundColor)
                            .shadow(.inner(color: .black.opacity(0.10), radius: 1.5, y: 1))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if track != nil {
                ArtworkView(url: artworkURL, cornerRadius: 0, size: .thumbnail)
                    .frame(width: 44, height: 44)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            // Music.app marks the artwork on hover to say the click swaps windows
            // rather than doing something to the track.
            if isHoveringArtwork {
                ZStack {
                    Rectangle().fill(.black.opacity(0.35))
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .onHover { isHoveringArtwork = $0 }
        .onTapGesture {
            NotificationCenter.default.post(name: .switchToMiniPlayer, object: nil)
        }
        .help("Switch to Mini Player")
    }
}

/// Volume only. The system route picker gets its own button: nesting it inside this
/// popover meant clicking it opened a second popover over the first.
struct VolumeControl: View {
    @Environment(PlayerService.self) private var player
    @State private var showingSlider = false
    var iconSize: CGFloat? = nil
    /// Hit and hover area around the glyph. Without it the row's button style draws its
    /// highlight tight around the speaker, which reads as a different control from the
    /// transport buttons beside it.
    var controlSize: CGFloat? = nil

    var body: some View {
        @Bindable var player = player
        Button { showingSlider.toggle() } label: {
            Image(systemName: iconName)
                .font(iconSize.map { .system(size: $0) })
                .foregroundStyle(.secondary)
                .frame(width: controlSize, height: controlSize)
        }
        .help("Volume")
        .accessibilityLabel("Volume")
        .popover(isPresented: $showingSlider, arrowEdge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 150)
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

/// Volume inline, as Music.app has it: a mute button, a short slider, and a full-volume
/// button. The popover version above stays for the mini player, where there's no room.
struct VolumeSlider: View {
    @Environment(PlayerService.self) private var player
    /// Restored when unmuting, so the button is a toggle rather than a one-way trip.
    @State private var volumeBeforeMute: Double?

    var body: some View {
        @Bindable var player = player
        HStack(spacing: 0) {
            Button {
                if let previous = volumeBeforeMute {
                    player.volume = previous
                    volumeBeforeMute = nil
                } else {
                    volumeBeforeMute = player.volume
                    player.volume = 0
                }
            } label: {
                Image(systemName: player.volume < 0.01 ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12))
                    .frame(width: playerControlSize, height: playerControlSize)
            }
            .help(player.volume < 0.01 ? "Unmute" : "Mute")
            .accessibilityLabel(player.volume < 0.01 ? "Unmute" : "Mute")

            Slider(value: $player.volume, in: 0...1)
                .controlSize(.mini)
                .frame(width: 72)
                .tint(.secondary)
                .accessibilityLabel("Volume")

            Button { player.volume = 1 } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .frame(width: playerControlSize, height: playerControlSize)
            }
            .help("Full Volume")
            .accessibilityLabel("Full Volume")
        }
        .buttonStyle(VolumeIconButtonStyle())
        .onChange(of: player.volume) { _, new in
            // Dragging the slider off zero is an unmute too.
            if new > 0.01 { volumeBeforeMute = nil }
        }
    }
}

struct ScrubberView: View {
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
