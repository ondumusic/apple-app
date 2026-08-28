#if os(macOS)
import AppKit
import SwiftUI

/// NSPanel-backed mini player. Floating HUD-style window so it can stay above the main
/// window across spaces. Content is SwiftUI via NSHostingView.
/// SwiftUI-observable window state — surfaces facts the layout needs to know
/// (whether the user is currently resizing) without the SwiftUI side polling.
@Observable @MainActor
final class MiniPlayerState {
    var isResizing: Bool = false
}

@MainActor
final class MiniPlayerWindowController: NSWindowController, NSWindowDelegate {
    private let hostingView: NSHostingView<AnyView>
    private let state = MiniPlayerState()
    /// Last height the user had when queue was visible (h > snap point). Restored
    /// when the queue toggle re-opens the queue. nil = use the default queue height.
    private var savedQueueOpenHeight: CGFloat?
    /// Last height the user had with queue collapsed. Restored when the queue
    /// toggle closes the queue.
    private var savedQueueClosedHeight: CGFloat?
    /// Enough room below the artwork for the transport plus a few queue rows. Relative
    /// to the artwork rather than absolute, so opening the queue adds space underneath
    /// instead of resizing the artwork.
    private var defaultQueueOpenHeight: CGFloat {
        (window?.frame.width ?? 300) + MiniPlayerContent.transportRowHeight + 220
    }

    /// UserDefaults key for the persisted window frame.
    private static let frameDefaultsKey = "MiniPlayerWindowFrame"
    /// Whether the mini player was open when the app last quit.
    static let visibleDefaultsKey = "MiniPlayerWindowVisible"
    private static var isTerminating = false
    /// Default frame — square (width × width), which puts the user in overlay mode
    /// where the artwork dominates and transport overlays at the bottom.
    private static let defaultFrame = NSRect(x: 0, y: 0, width: 300, height: 300)

    init(player: PlayerService) {
        // Plain NSWindow with hidden title bar so the artwork extends edge-to-edge.
        // Restore the user's last frame, or fall back to the square overlay default.
        let savedFrame = Self.loadSavedFrame()
        let initialFrame = savedFrame ?? Self.defaultFrame
        let panel = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Now Playing"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // Movable-by-window-background was capturing drags meant for queue rows
        // (drag-to-reorder also moved the window). Window can still be dragged
        // from the title bar strip at the top.
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 240, height: 64)
        panel.maxSize = NSSize(width: 540, height: 900)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Hosting view set up first; queue toggle plumbed in after super.init so we
        // can capture self.
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.translatesAutoresizingMaskIntoConstraints = false
        if let cv = panel.contentView {
            cv.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                host.topAnchor.constraint(equalTo: cv.topAnchor),
                host.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
        }
        self.hostingView = host
        if savedFrame == nil { panel.center() }
        super.init(window: panel)
        panel.delegate = self

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Self.isTerminating = true }
        }

        // Now that self exists we can wire the queue toggle through. Toggle is
        // intent-only — the controller decides expand vs collapse based on the
        // current window height, which keeps SwiftUI state in sync with reality
        // even after the user resizes manually.
        let content = MiniPlayerContent(onQueueToggleRequest: { [weak self] in
            self?.toggleQueueByWindowState()
        })
        .environment(player)
        .environment(state)
        host.rootView = AnyView(content)
    }

    /// Derives current queue-visibility from window height and flips it.
    private func toggleQueueByWindowState() {
        guard let window else { return }
        let snapPoint = window.frame.width + Self.transportRowHeight
        let isVisible = window.frame.height > snapPoint
        applyQueueExpansion(expanded: !isVisible)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if isVisible {
            close()
        } else {
            showWindow(nil)
            UserDefaults.standard.set(true, forKey: Self.visibleDefaultsKey)
        }
    }

    /// Resizes the window to show or hide the inline queue panel. Remembers the
    /// height the user had with queue closed so toggling-off restores it; remembers
    /// the height with queue open so toggling-on later returns to the same size.
    private func applyQueueExpansion(expanded: Bool) {
        guard let window else { return }
        var frame = window.frame
        let topY = frame.maxY
        if expanded {
            // Save current as "queue closed" height; apply saved or default open
            // height.
            savedQueueClosedHeight = frame.height
            // Has to clear the not-committed band, or the resize-end snap immediately
            // pulls it shut again — which looked like the button toggling by a few px
            // and closing itself.
            let minOpen = frame.width + MiniPlayerContent.transportRowHeight + Self.minCommittedQueueHeight
            frame.size.height = max(savedQueueOpenHeight ?? defaultQueueOpenHeight, minOpen)
        } else {
            // Save current as "queue open" height; apply saved or snap-point
            // closed height.
            savedQueueOpenHeight = frame.height
            frame.size.height = savedQueueClosedHeight ?? frame.width
        }
        frame.origin.y = topY - frame.size.height
        // The transport travels from overlaying the artwork to sitting below it during
        // this animation. Without the resizing flag it is hover-gated for part of that
        // journey and blinks out halfway.
        state.isResizing = true
        animateFrameChange(window: window, to: frame, duration: Self.queueAnimationDuration) { [weak self] in
            self?.state.isResizing = false
        }
    }

    /// Faster window-size animation than `setFrame(_:display:animate:)` default.
    private func animateFrameChange(
        window: NSWindow,
        to frame: NSRect,
        duration: TimeInterval,
        completion: (@MainActor () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    /// On resize-end, snap into one of three resting positions:
    /// 1. Half-overlap zone (h ∈ (w, w + transport]): transport is partially over
    ///    the artwork. Snap to nearest edge — full overlay (h = w) or transport
    ///    just below (h = w + transport).
    /// 2. Queue-not-committed zone (h ∈ (w + transport, w + transport + commit)):
    ///    snap back to "transport just below" so a peek doesn't stick.
    /// Both snaps are animated.
    nonisolated func windowDidEndLiveResize(_ notification: Notification) {
        Task { @MainActor in
            self.state.isResizing = false
            guard let window = self.window else { return }
            let frame = window.frame
            let w = frame.width
            let h = frame.height
            let transport = Self.transportRowHeight
            let snapPoint = w + transport
            let minCommittedQueueHeight = Self.minCommittedQueueHeight

            var targetHeight: CGFloat? = nil
            if h > w && h <= snapPoint {
                // Half-overlap zone — snap to nearest edge.
                let overlap = h - w
                targetHeight = overlap < transport / 2 ? w : snapPoint
            } else if h > snapPoint && h < snapPoint + minCommittedQueueHeight {
                // Queue not committed.
                targetHeight = snapPoint
            }

            if let target = targetHeight, abs(target - h) > 1 {
                var newFrame = frame
                let topY = frame.maxY
                newFrame.size.height = target
                newFrame.origin.y = topY - target
                animateFrameChange(window: window, to: newFrame, duration: 0.18)
            }

            // After settle, persist new frame and update queue-height memory.
            saveCurrentFrame()
            updateSavedQueueHeights(currentHeight: window.frame.height)
        }
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in self.saveCurrentFrame() }
    }

    /// Quitting closes the window too, so a plain windowWillClose would record "not
    /// visible" for every launch — the state we want is what the user last chose, not
    /// the teardown that follows it.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard !Self.isTerminating else { return }
            UserDefaults.standard.set(false, forKey: Self.visibleDefaultsKey)
        }
    }

    nonisolated func windowWillStartLiveResize(_ notification: Notification) {
        Task { @MainActor in self.state.isResizing = true }
    }

    /// The artwork is a square sized by the window's width, so a window shorter than it
    /// is wide could only ever crop it into a meaningless band. Height below the artwork
    /// is what reveals the transport and queue; drag well past the artwork and the window
    /// collapses to the compact bar instead.
    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        let compactMax = MiniPlayerContent.compactMaxHeight
        if size.height < size.width * 0.4 {
            size.height = min(max(size.height, sender.minSize.height), compactMax)
        } else {
            size.height = max(size.height, size.width)
        }
        return size
    }

    private func updateSavedQueueHeights(currentHeight h: CGFloat) {
        guard let window else { return }
        let snapPoint = window.frame.width + Self.transportRowHeight
        // Only remember a height that actually shows a queue; a sliver above the snap
        // point would be restored on the next open and then snapped shut.
        if h >= snapPoint + Self.minCommittedQueueHeight {
            savedQueueOpenHeight = h
        } else if h <= snapPoint {
            savedQueueClosedHeight = h
        }
    }

    private func saveCurrentFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameDefaultsKey)
    }

    private static func loadSavedFrame() -> NSRect? {
        guard let str = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) else { return nil }
        let rect = NSRectFromString(str)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    /// Below this much queue showing, the panel isn't really open — resizing snaps back
    /// rather than leaving a sliver, and expanding must clear it or the two rules fight.
    static let minCommittedQueueHeight: CGFloat = 100

    /// Long enough to read as motion, eased at both ends. The previous 0.18s easeOut
    /// put 40% of the travel in the first frame, so the window appeared to jump.
    static let queueAnimationDuration: TimeInterval = 0.32

    /// Snap geometry has to agree with the layout, so read it from the layout.
    private static var transportRowHeight: CGFloat { MiniPlayerContent.transportRowHeight }
}

/// Three layout states purely driven by window height:
///   compact (<= 80pt): toolbar-style row — tiny artwork, title, transport
///   overlay (80–360pt): artwork covers window, transport fades over the bottom
///       on hover (Apple Music–style mini)
///   stacked (>= 360pt): square artwork on top, transport row below, queue list
///       progressively revealed as the window grows further
/// The queue toggle just animates the window height; once the height crosses
/// the stacked threshold the queue area becomes visible naturally.
private struct MiniPlayerContent: View {
    @Environment(PlayerService.self) private var player
    /// Asks the window controller to flip queue visibility. Controller decides
    /// expand vs collapse based on actual current window height — keeps SwiftUI
    /// state in sync with reality even after a manual resize.
    let onQueueToggleRequest: () -> Void

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? {
        guard player.queue.indices.contains(player.effectiveIndex) else { return nil }
        return player.queue[player.effectiveIndex].artworkURL
    }

    /// Height reserved for the transport row's content area (title + controls +
    /// scrubber + padding). Used to compute the snap point and transport position.
    /// Must fit title, artist, the transport row, the elapsed/remaining labels and the
    /// scrubber. Undersized, the row is pinned to the window's bottom edge and the
    /// scrubber is clipped straight off it.
    static let transportRowHeight: CGFloat = 126
    static let compactMaxHeight: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if h <= Self.compactMaxHeight {
                CompactLayout(track: track, artworkURL: artworkURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UnifiedLayout(
                    track: track,
                    artworkURL: artworkURL,
                    width: w,
                    height: h,
                    onQueueToggleRequest: onQueueToggleRequest
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // ignoresSafeArea — the window uses .fullSizeContentView so the contentView
        // extends under the title bar. SwiftUI's default safe-area inset would push
        // our artwork down by the title-bar height; bypassing it lets the artwork
        // genuinely fill the top of the window.
        .ignoresSafeArea()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Unified non-compact layout
/// Unified non-compact layout. Single layout that handles every height between
/// `compactMaxHeight` and the maximum:
///
///   • Artwork is a square at the top sized to `min(width, height)` — when window
///     can't fit a full square, artwork covers the available area (cover-center).
///   • Transport row position is `min(height - transportHeight, artworkHeight)`:
///     when window is short, the row hugs the bottom edge and travels with the
///     resize cursor; when window is tall enough for artwork + transport to both
///     fit, the row "lands" just below the artwork and stops moving.
///   • Queue list reveals progressively in any space below transport.
///
/// One stable view structure across the entire range — no mode swap, no flicker.
private struct UnifiedLayout: View {
    @Environment(PlayerService.self) private var player
    @Environment(MiniPlayerState.self) private var windowState
    let track: Track?
    let artworkURL: URL?
    let width: CGFloat
    let height: CGFloat
    let onQueueToggleRequest: () -> Void

    @State private var isHovering = false
    @State private var hideTask: Task<Void, Never>?

    /// Square, sized by width alone. Deriving it from height too meant a short window
    /// cropped the artwork into a band, and anything that changed the height — opening
    /// the queue, for one — resized the artwork with it.
    private var artworkHeight: CGFloat { width }
    private var transportTopY: CGFloat {
        // Transport stays glued to the window's bottom edge until it would dip
        // below the artwork; from there on it locks at the artwork's bottom.
        min(max(0, height - MiniPlayerContent.transportRowHeight), artworkHeight)
    }
    private var transportOverlapsArtwork: Bool { transportTopY < artworkHeight }
    private var queueAreaHeight: CGFloat {
        max(0, height - artworkHeight - MiniPlayerContent.transportRowHeight)
    }
    private var isQueueVisible: Bool { queueAreaHeight > 0 }
    /// Transport visible when below the artwork (always), or when the user is
    /// hovering, or while the window is being resized (so it stays glued to the
    /// bottom edge during the drag instead of fading away mid-resize).
    private var transportVisible: Bool {
        !transportOverlapsArtwork || isHovering || windowState.isResizing
    }

    var body: some View {
        ZStack(alignment: .top) {
            artwork
                .frame(width: width, height: artworkHeight)
                .clipped()
            // Transport (and any revealed queue) positioned absolutely via a leading
            // VStack with a top spacer.
            VStack(spacing: 0) {
                Color.clear.frame(height: transportTopY)
                TransportRow(
                    track: track,
                    isQueueVisible: isQueueVisible,
                    onQueueToggleRequest: onQueueToggleRequest
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(transportBackground)
                .opacity(transportVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: transportVisible)
                if queueAreaHeight > 0 {
                    Divider()
                    InlineQueue()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { hovering in
            hideTask?.cancel()
            if hovering {
                isHovering = true
            } else {
                hideTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    isHovering = false
                }
            }
        }
    }

    @ViewBuilder
    private var transportBackground: some View {
        if transportOverlapsArtwork {
            // Translucent material when over the artwork — adapts to the system
            // appearance and keeps the (black) text legible without obscuring the
            // image too aggressively. Black-on-material reads in both modes so the
            // controls don't visually flicker color when the snap happens.
            Rectangle().fill(.regularMaterial)
        } else {
            Color(NSColor.windowBackgroundColor)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if track != nil, let url = artworkURL {
            ArtworkView(url: url, cornerRadius: 0)
        } else {
            ArtworkPlaceholder()
        }
    }
}

// MARK: - Compact layout (toolbar height)

/// Tight horizontal layout for when the window is squashed to toolbar height. Tiny
/// artwork on the left, title in the middle, transport buttons on the right.
private struct CompactLayout: View {
    @Environment(PlayerService.self) private var player
    let track: Track?
    let artworkURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let url = artworkURL {
                    ArtworkView(url: url)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.4))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(track?.name ?? "Not Playing")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let track {
                    Text(track.artist.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                Button { player.back() } label: {
                    Image(systemName: "backward.fill")
                }
                .disabled(track == nil || !player.canGoBack)
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                .disabled(track == nil)
                Button { player.skip() } label: {
                    Image(systemName: "forward.fill")
                }
                .disabled(track == nil || !player.canSkip)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}

// MARK: - Transport row (used by standard + expanded layouts)

private struct MiniVolume: View {
    @Environment(PlayerService.self) private var player
    let tint: Color?

    @State private var showingSlider = false

    /// An always-visible slider crowds a window that can be 240pt wide, so this follows
    /// Music.app: a speaker button that reflects the level and opens the slider on click.
    var body: some View {
        @Bindable var player = player
        Button { showingSlider.toggle() } label: {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint.map { $0.opacity(0.85) } ?? Color.secondary)
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

private struct TransportRow: View {
    @Environment(PlayerService.self) private var player
    let track: Track?
    let isQueueVisible: Bool
    let onQueueToggleRequest: () -> Void
    var tintForeground: Color? = nil

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text(track?.name ?? "Not Playing")
                    .font(.headline)
                    .lineLimit(1)
                if let track {
                    Text(track.artist.name)
                        .font(.subheadline)
                        .foregroundStyle(tintForeground.map { $0.opacity(0.85) } ?? Color.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(tintForeground ?? Color.primary)

            // Two-layer ZStack so the play button stays centered horizontally even
            // though the queue toggle lives to the right. Explicit frames on each
            // button so the row's intrinsic width is predictable and stays inside
            // the parent's bounds — implicit `.title3` widths were stacking up
            // wider than the narrow mini-player window in overlay mode.
            ZStack {
                HStack(spacing: 18) {
                    Button { player.back() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16))
                            .frame(width: 24, height: 24)
                    }
                    .disabled(track == nil || !player.canGoBack)
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(track == nil)
                    Button { player.skip() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .frame(width: 24, height: 24)
                    }
                    .disabled(track == nil || !player.canSkip)
                }
                // Mirrors the queue toggle on the opposite side so the play button stays
                // centred between them.
                HStack(spacing: 0) {
                    MiniVolume(tint: tintForeground)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Spacer()
                    Button { onQueueToggleRequest() } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .disabled(track == nil)
                    .foregroundStyle(isQueueVisible
                        ? AnyShapeStyle(Color.accentColor)
                        : tintForeground.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.primary))
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .foregroundStyle(tintForeground ?? Color.primary)

            if track != nil {
                MiniScrubber(tint: tintForeground)
            }
        }
    }
}

/// Inline queue rendered below the player in the mini window when the queue toggle
/// is on. Reuses the main slide-over's QueueList so interaction behavior matches.
private struct InlineQueue: View {
    @Environment(PlayerService.self) private var player

    private var upNext: [(originalIndex: Int, item: QueueItem)] {
        let current = player.effectiveIndex
        return player.queue.enumerated()
            .compactMap { current >= 0 && $0.offset > current ? ($0.offset, $0.element) : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            if upNext.isEmpty {
                Spacer()
                Text("Nothing up next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                QueueList(upNext: upNext, rowHeight: 40, showsDuration: false)
            }
        }
    }
}

private struct ArtworkPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [.gray.opacity(0.35), .gray.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct MiniScrubber: View {
    @Environment(PlayerService.self) private var player
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false
    var tint: Color? = nil

    var body: some View {
        let resolvedTint = tint ?? Color.accentColor
        let trackColor = (tint ?? .secondary).opacity(0.3)
        let labelColor: Color = tint?.opacity(0.85) ?? Color.secondary
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Text(format(isScrubbing ? scrubValue : player.progress))
                Spacer()
                Text(format(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(labelColor)
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
                },
                tint: resolvedTint,
                trackColor: trackColor
            )
            .frame(height: 10)
        }
    }

    private func format(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
