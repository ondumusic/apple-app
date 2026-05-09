#if os(macOS)
import AppKit
import SwiftUI

/// NSPanel-backed mini player. Floating HUD-style window so it can stay above the main
/// window across spaces. Content is SwiftUI via NSHostingView.
@MainActor
final class MiniPlayerWindowController: NSWindowController, NSWindowDelegate {
    private let hostingView: NSHostingView<AnyView>
    /// Set when the queue panel is open below the player; non-nil = the height to
    /// restore when the queue panel collapses again.
    private var heightBeforeQueueExpand: CGFloat?
    private static let queuePanelHeight: CGFloat = 280

    init(player: PlayerService) {
        // Plain NSWindow with hidden title bar so the artwork extends edge-to-edge.
        // The window is non-square — artwork on top, transport controls below — and
        // can be resized along both axes within minSize bounds.
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 340),
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
        panel.minSize = NSSize(width: 240, height: 56)
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
        panel.center()
        super.init(window: panel)
        panel.delegate = self

        // Now that self exists we can wire the queue toggle through. The SwiftUI view
        // owns whether the queue is visible (for layout); the callback only resizes
        // the window to accommodate it.
        let content = MiniPlayerContent(onToggleQueue: { [weak self] expanded in
            self?.applyQueueExpansion(expanded: expanded)
        })
        .environment(player)
        host.rootView = AnyView(content)
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

    /// Grows the window downward to reveal the inline queue panel, or collapses
    /// back to the previous height. Anchored to the top edge so the artwork stays
    /// in place visually.
    private func applyQueueExpansion(expanded: Bool) {
        guard let window else { return }
        var frame = window.frame
        if expanded {
            guard heightBeforeQueueExpand == nil else { return }
            heightBeforeQueueExpand = frame.height
            let topY = frame.maxY
            frame.size.height += Self.queuePanelHeight
            frame.origin.y = topY - frame.size.height
        } else {
            guard let saved = heightBeforeQueueExpand else { return }
            let topY = frame.maxY
            frame.size.height = saved
            frame.origin.y = topY - saved
            heightBeforeQueueExpand = nil
        }
        window.setFrame(frame, display: true, animate: true)
    }

    /// Window resize/zoom can drop us below the queue panel's expand threshold —
    /// keep `heightBeforeQueueExpand` in sync so the next toggle still does the
    /// right thing.
    nonisolated func windowDidEndLiveResize(_ notification: Notification) {
        Task { @MainActor in
            // If the user manually shrank the window below where queue would fit,
            // forget the saved height so subsequent toggles use current state.
            guard let window = self.window else { return }
            if let saved = heightBeforeQueueExpand, window.frame.height < saved + 40 {
                heightBeforeQueueExpand = nil
            }
        }
    }
}

/// Three layout states based on window height:
///   compact (<= 80pt): toolbar-style row — tiny artwork, title, transport
///   medium (80–460pt, no queue): artwork covers window, transport overlays on hover
///   big (>= 460pt OR queue toggled): square artwork on top, transport stacked below,
///       optional queue list at the bottom
private struct MiniPlayerContent: View {
    @Environment(PlayerService.self) private var player
    /// Notifies the window controller to grow / shrink to fit the queue panel.
    let onToggleQueue: (Bool) -> Void
    @State private var showQueue: Bool = false

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? {
        guard player.queue.indices.contains(player.effectiveIndex) else { return nil }
        return player.queue[player.effectiveIndex].artworkURL
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            Group {
                if h <= 80 {
                    CompactLayout(track: track, artworkURL: artworkURL)
                } else if showQueue || h >= 460 {
                    StackedLayout(track: track, artworkURL: artworkURL, showQueue: showQueue, toggleQueue: toggleQueue)
                } else {
                    OverlayLayout(track: track, artworkURL: artworkURL, showQueue: showQueue, toggleQueue: toggleQueue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // ignoresSafeArea — the window uses .fullSizeContentView so the contentView
        // extends under the title bar. SwiftUI's default safe-area inset would push
        // our artwork down by the title-bar height; bypassing it lets the artwork
        // genuinely fill the top of the window.
        .ignoresSafeArea()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toggleQueue() {
        showQueue.toggle()
        onToggleQueue(showQueue)
    }
}

// MARK: - Standard layout (default)

/// Square artwork on top, transport row below. The default mini-player look.
/// Big mode: square artwork pinned to the top (always full window width), transport
/// row below, queue list always rendered at the bottom. When the window is just tall
/// enough for artwork + transport, the queue takes 0pt and is invisible. Dragging
/// the window taller (or pressing the queue toggle) reveals the queue area
/// progressively — no separate "show queue" rendering path that would force a
/// re-layout / artwork flicker.
private struct StackedLayout: View {
    @Environment(PlayerService.self) private var player
    let track: Track?
    let artworkURL: URL?
    let showQueue: Bool
    let toggleQueue: () -> Void

    var body: some View {
        // GeometryReader at the outer level so artwork can be pinned to the window's
        // exact width — `.aspectRatio(1, contentMode: .fit)` was shrinking artwork to
        // a centered square at narrower-than-tall windows.
        GeometryReader { geo in
            let w = geo.size.width
            VStack(spacing: 0) {
                artwork
                    .frame(width: w, height: w)
                    .clipped()
                TransportRow(track: track, showQueue: showQueue, toggleQueue: toggleQueue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color(NSColor.windowBackgroundColor))
                Divider()
                InlineQueue()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
            }
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

// MARK: - Expanded layout (tall window)

/// Artwork fills available space, transport controls slide in over the bottom on
/// hover — same behavior as macOS's full-screen Now Playing.
/// Medium mode: artwork covers the whole window (background-cover style), transport
/// controls fade in over the bottom on hover. Apple Music's default mini look.
private struct OverlayLayout: View {
    @Environment(PlayerService.self) private var player
    let track: Track?
    let artworkURL: URL?
    let showQueue: Bool
    let toggleQueue: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if hovering {
                TransportRow(track: track, showQueue: showQueue, toggleQueue: toggleQueue, tintForeground: .white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
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

private struct TransportRow: View {
    @Environment(PlayerService.self) private var player
    let track: Track?
    let showQueue: Bool
    let toggleQueue: () -> Void
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
            // though the queue toggle lives to the right. Centered HStack holds the
            // main transport; the trailing HStack pushes the queue button to the
            // right edge without affecting the centered layout.
            ZStack {
                HStack(spacing: 26) {
                    Button { player.back() } label: {
                        Image(systemName: "backward.fill").font(.title3)
                    }
                    .disabled(track == nil || !player.canGoBack)
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                    }
                    .disabled(track == nil)
                    Button { player.skip() } label: {
                        Image(systemName: "forward.fill").font(.title3)
                    }
                    .disabled(track == nil || !player.canSkip)
                }
                HStack {
                    Spacer()
                    Button { toggleQueue() } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                    }
                    .disabled(track == nil)
                    .foregroundStyle(showQueue
                        ? AnyShapeStyle(Color.accentColor)
                        : tintForeground.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.primary))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(tintForeground ?? Color.primary)

            if track != nil {
                MiniScrubber(tint: tintForeground)
            }
        }
    }
}

/// Inline queue rendered below the player in the mini window when the queue toggle
/// is on. Shows up-next only (items after the currently-playing index) with
/// artwork thumbnails. Editable via swipe-to-remove + drag-to-reorder.
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
                List {
                    ForEach(upNext, id: \.item.id) { entry in
                        InlineQueueRow(originalIndex: entry.originalIndex, item: entry.item)
                            .focusEffectDisabled()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    player.removeFromQueue(at: IndexSet(integer: entry.originalIndex))
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    .onMove { source, destination in
                        let originalSource = IndexSet(source.compactMap {
                            upNext.indices.contains($0) ? upNext[$0].originalIndex : nil
                        })
                        let originalDest: Int = {
                            if destination >= upNext.count {
                                return (upNext.last?.originalIndex ?? player.effectiveIndex) + 1
                            }
                            return upNext[destination].originalIndex
                        }()
                        player.moveQueueItems(from: originalSource, to: originalDest)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct InlineQueueRow: View {
    @Environment(PlayerService.self) private var player
    let originalIndex: Int
    let item: QueueItem

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(url: item.artworkURL, cornerRadius: 3)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.track.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(item.track.artist.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            player.skipTo(queueIndex: originalIndex)
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
        HStack(spacing: 6) {
            Text(format(isScrubbing ? scrubValue : player.progress))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(tint?.opacity(0.85) ?? Color.secondary)
                .frame(width: 36, alignment: .trailing)
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
            .frame(height: 12)
            Text(format(player.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(tint?.opacity(0.85) ?? Color.secondary)
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
