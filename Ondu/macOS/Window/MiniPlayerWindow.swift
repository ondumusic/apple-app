#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI

// The mini player: current artwork, transport and, at taller sizes, the queue.
//
// A plain NSWindow, not an NSPanel — it has to take key status for its own controls and
// text. It joins all spaces, but it sits at the normal window level and only rises above
// other apps when "Keep Mini Player on Top" is on. Content is SwiftUI via NSHostingView.

/// Carries Cmd+W, which nothing else will.
///
/// File ▸ Close belongs to SwiftUI here, and it only validates against SwiftUI's own
/// scenes. This window isn't one, so with it in front the menu item is disabled, the
/// key equivalent goes unclaimed and AppKit beeps.
private final class MiniPlayerWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            event.charactersIgnoringModifiers == "w"
        {
            // close() rather than performClose(), which works by highlighting the close
            // button and silently declines when it can't: this window keeps that button
            // at zero alpha until the pointer is inside, so Cmd+W worked or didn't
            // depending on where the mouse happened to be.
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

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

    /// Lets the main window tell which of the two is key. It's a plain NSWindow, not an
    /// NSPanel, so canBecomeMain is true for it and couldn't separate them.
    static let windowIdentifier = NSUserInterfaceItemIdentifier("Ondu.miniPlayer")

    /// UserDefaults key for the persisted window frame.
    private static let frameDefaultsKey = "MiniPlayerWindowFrame"
    /// Whether the mini player was open when the app last quit.
    static let visibleDefaultsKey = "MiniPlayerWindowVisible"
    /// Whether the mini player — rather than the main window — was the one the user was
    /// last working in. Relaunch restores key to whichever it was.
    static let lastKeyDefaultsKey = "MiniPlayerWasLastKeyWindow"
    private static var isTerminating = false
    private static var isClosingForSignOut = false
    private static var didClearInitialFocus = false
    /// Default frame — square (width × width), which puts the user in overlay mode
    /// where the artwork dominates and transport overlays at the bottom.
    private static let defaultFrame = NSRect(x: 0, y: 0, width: 300, height: 300)

    init(player: PlayerService, settings: SettingsStore, musicLibrary: MusicLibrary, network: NetworkMonitor) {
        // Plain NSWindow with hidden title bar so the artwork extends edge-to-edge.
        // Restore the user's last frame, or fall back to the square overlay default.
        let savedFrame = Self.loadSavedFrame()
        let initialFrame = savedFrame ?? Self.defaultFrame
        let panel = MiniPlayerWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Now Playing"
        panel.identifier = Self.windowIdentifier
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
        // Out of the way of the artwork until the pointer is in the window. Alpha rather
        // than isHidden so it can fade, and because a hidden button stops being clickable
        // — by the time the pointer reaches the corner the window has already revealed it.
        panel.standardWindowButton(.closeButton)?.alphaValue = 0

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

            // Above the hosting view so nothing covers it, and transparent to clicks so
            // the player underneath still gets them. A tracking area on the hosting view
            // itself isn't an option — it's SwiftUI's to own and resize.
            let probe = WindowHoverProbe()
            probe.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(probe)
            NSLayoutConstraint.activate([
                probe.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                probe.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                probe.topAnchor.constraint(equalTo: cv.topAnchor),
                probe.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
            probe.onHoverChange = { [weak panel] inside in
                guard let button = panel?.standardWindowButton(.closeButton) else { return }
                guard inside else {
                    // Gone outright rather than faded. A traffic light is a saturated dot
                    // inside a pale ring, and every way of fading it — plain alphaValue,
                    // or layer-backed so it composites as one bitmap — loses the red well
                    // before the ring, which reads as the colour dropping out and a grey
                    // circle hanging behind it. The delay above is the softener instead.
                    button.alphaValue = 0
                    return
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    context.allowsImplicitAnimation = true
                    button.animator().alphaValue = 1
                }
            }
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

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow else { return }
                Self.recordKeyWindowPreference(keyWindow: window, panel: panel)
                // Clearing in init doesn't hold: AppKit assigns a first responder when
                // the window first becomes key, which is after that. Only the first
                // time — after that, whatever the user focused is theirs.
                if window === panel, !Self.didClearInitialFocus {
                    Self.didClearInitialFocus = true
                    window.makeFirstResponder(nil)
                }
            }
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
        .environment(settings)
        // NSHostingView starts a fresh environment scope, so the queue table's actions
        // have to be handed these explicitly.
        .environment(musicLibrary)
        .environment(network)
        // Clearing the window's first responder isn't enough on its own: SwiftUI runs
        // its own focus inside the hosting view and rings whichever control it picks,
        // which is the volume button. Nothing in this HUD benefits from a focus ring.
        .focusEffectDisabled()
        host.rootView = AnyView(content)
        observeUpNextShortcut()

        // Nothing focused at launch. AppKit otherwise parks focus on the first control
        // it finds — the volume button — where Space and Return would act on it, and
        // Space is already play/pause everywhere else.
        panel.initialFirstResponder = nil
        panel.makeFirstResponder(nil)
    }

    /// Remembers which of the two windows the user was last working in so relaunch can
    /// restore the same one. Recorded when a window *becomes* key rather than inferred
    /// from the panel resigning: at resignKey the incoming window isn't installed yet,
    /// so NSApp.keyWindow reads nil and the hand-off goes unrecorded.
    private static func recordKeyWindowPreference(keyWindow: NSWindow, panel: NSWindow) {
        guard !isTerminating else { return }
        guard keyWindow === panel || keyWindow.canBecomeMain else { return }
        // On quit the main window goes away first and key falls to the panel, which
        // would otherwise overwrite the preference with the opposite of what the user
        // left. A hand-off only counts while there's still a main window to hand to.
        guard NSApp.windows.contains(where: { $0 !== panel && $0.isVisible && $0.canBecomeMain })
        else { return }
        UserDefaults.standard.set(keyWindow === panel, forKey: lastKeyDefaultsKey)
    }

    /// The shortcut reaches every window, so the mini player only claims it while it has
    /// focus — otherwise the main window's slide-over is the queue the user means.
    private func observeUpNextShortcut() {
        NotificationCenter.default.addObserver(
            forName: .toggleUpNext, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.isKeyWindow == true else { return }
                self.toggleQueueByWindowState()
            }
        }
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

    /// Restores the window at launch in the z-order and focus the user left it in.
    ///
    /// Deferred a tick so the main window is on screen to order against. Ordering the
    /// panel front and raising the main window afterwards put the mini player up front on
    /// every single launch and then visibly flipped; going straight in behind the main
    /// window means there's nothing to correct. showWindow(_:) is no good either — it
    /// makes the panel key and front, stealing focus and leaving the main window's
    /// toolbar rendering as an inactive window's.
    func restoreAtLaunch() {
        Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }
            UserDefaults.standard.set(true, forKey: Self.visibleDefaultsKey)
            if UserDefaults.standard.bool(forKey: Self.lastKeyDefaultsKey) {
                window.makeKeyAndOrderFront(nil)
            } else if let main = NSApp.windows.first(where: {
                $0 !== window && $0.isVisible && $0.canBecomeMain
            }) {
                window.order(.below, relativeTo: main.windowNumber)
            } else {
                window.orderFront(nil)
            }
        }
    }

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
            // Same reasoning as terminating: signing out isn't the user putting the
            // window away, so it shouldn't decide what comes back on the next launch.
            if Self.isClosingForSignOut {
                Self.isClosingForSignOut = false
                return
            }
            UserDefaults.standard.set(false, forKey: Self.visibleDefaultsKey)
        }
    }

    /// Signing out empties the library, so the mini player has nothing left to show.
    /// Static because the window outlives the view that owns the controller: the main
    /// window's content is torn down at sign-out and can't close this itself.
    static func closeForSignOut() {
        guard let window = NSApp.windows.first(where: { $0.identifier == windowIdentifier })
        else { return }
        isClosingForSignOut = true
        window.close()
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
    @Environment(SettingsStore.self) private var settings
    /// Asks the window controller to flip queue visibility. Controller decides
    /// expand vs collapse based on actual current window height — keeps SwiftUI
    /// state in sync with reality even after a manual resize.
    let onQueueToggleRequest: () -> Void

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? { player.currentArtworkURL }

    /// The mini player is the one Mac surface where an artwork tint reads as intended
    /// rather than as a rendering fault: a small window that becomes the record's colour.
    /// The main window's player bar is a thin strip inside full app chrome, and is left
    /// alone deliberately.
    /// The blurred cover is the tint now, so "do we have artwork" is the only question —
    /// no need to decode one to find out.
    private var isTinted: Bool { player.tintsFromArtwork }

    /// Floating is scoped to the app being in the background — see MiniPlayerWindowLevel.
    @State private var isAppActive = NSApp.isActive

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
                    isTinted: isTinted,
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
        .background {
            Group {
                if isTinted {
                    // PROTOTYPE: the cover itself, blurred, instead of a gradient built
                    // from its average colour.
                    GeometryReader { g in
                        if g.size.height <= Self.compactMaxHeight {
                            // A radius suited to an 80pt strip; the full-size one washes
                            // it out to a single colour.
                            ArtworkBackdrop(url: artworkURL, blurRadius: 16, dimming: 0.5)
                        } else {
                            VStack(spacing: 0) {
                                // Skip the band the real artwork already fills. Covering
                                // it achieved nothing visible and forced a square cover
                                // to fill a tall narrow window, so the only part on show
                                // was a thin vertical slice out of the middle.
                                Color.clear.frame(height: g.size.width)
                                ArtworkBackdrop(url: artworkURL)
                            }
                        }
                    }
                } else {
                    Rectangle().fill(.windowBackground)
                }
            }
            // The background needs the same safe-area bypass the content above has, or it
            // stops at the title-bar inset and the window's own colour shows as a band
            // across the top. Full-bleed artwork used to hide that.
            .ignoresSafeArea()
        }
        // The chosen accent was picked against neutral chrome and clashes on top of an
        // arbitrary artwork colour; white sits on any of them.
        .accentColor(isTinted ? .white : settings.resolvedAccentColor)
        // Keyed on the same answer the background uses, so a window with no cover to
        // show doesn't go dark around white controls. Known synchronously — nothing here
        // waits on decoding a colour out of the artwork, so there's no flash to avoid.
        .background(WindowAppearance(isDark: isTinted))
        .background(
            MiniPlayerWindowLevel(
                isFloating: settings.miniPlayerAlwaysOnTop && !isAppActive)
        )
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAppActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            isAppActive = false
        }
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
    /// Whether the window is showing an artwork tint, in which case the chrome below the
    /// artwork gets out of the way and lets the gradient behind it through.
    let isTinted: Bool
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
                .gesture(WindowDragGesture())
            // Transport (and any revealed queue) positioned absolutely via a leading
            // VStack with a top spacer.
            VStack(spacing: 0) {
                Color.clear.frame(height: transportTopY)
                TransportRow(
                    track: track,
                    isQueueVisible: isQueueVisible,
                    onQueueToggleRequest: onQueueToggleRequest,
                    tintForeground: isTinted ? .white : nil
                )
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .frame(
                    maxWidth: .infinity,
                    minHeight: MiniPlayerContent.transportRowHeight,
                    maxHeight: MiniPlayerContent.transportRowHeight
                )
                .background(transportBackground)
                .opacity(transportVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: transportVisible)
                if queueAreaHeight > 0 {
                    Divider()
                    InlineQueue()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Clear would leave the queue and the transport on one
                        // undifferentiated wash; this darkens the band the way the opaque
                        // window background used to separate them.
                        .background(
                            isTinted
                                ? AnyShapeStyle(Color.black.opacity(0.22))
                                : AnyShapeStyle(.windowBackground))
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
            Rectangle().fill(.regularMaterial).gesture(WindowDragGesture())
        } else if isTinted {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
        } else {
            Rectangle().fill(.windowBackground).gesture(WindowDragGesture())
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if track != nil, let url = artworkURL {
            // Sized to the window, not left to ArtworkView's 300px default: this is the
            // largest the artwork is shown anywhere in the app — up to 540pt, so 1080
            // pixels on a Retina display — and 300 was being upscaled more than 3x.
            ArtworkView(url: url, cornerRadius: 0, size: .large)
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
                    // The same default was wrong the other way here: 300px decoded for a
                    // 40pt thumbnail.
                    ArtworkView(url: url, size: .thumbnail)
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
            HStack(spacing: 4) {
                Button {
                    player.back()
                } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 26, height: 26)
                }
                .accessibilityLabel("Previous")
                .disabled(track == nil || !player.canGoBack)
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .frame(width: 26, height: 26)
                }
                .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Play"))
                .disabled(track == nil)
                Button {
                    player.skip()
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 26, height: 26)
                }
                .accessibilityLabel("Next")
                .disabled(track == nil || !player.canSkip)
            }
            .buttonStyle(PlayerControlButtonStyle())
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
    let isQueueVisible: Bool
    let onQueueToggleRequest: () -> Void
    var tintForeground: Color? = nil

    /// Every control in the row is the same size, as in the player bar — play is set
    /// apart by its glyph, not by a bigger button.
    private static let controlSize: CGFloat = playerControlSize

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
                HStack(spacing: 0) {
                    Button {
                        player.back()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                            .frame(width: Self.controlSize, height: Self.controlSize)
                    }
                    .accessibilityLabel("Previous")
                    .disabled(track == nil || !player.canGoBack)
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19))
                            .frame(width: Self.controlSize, height: Self.controlSize)
                    }
                    .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Play"))
                    .disabled(track == nil)
                    Button {
                        player.skip()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                            .frame(width: Self.controlSize, height: Self.controlSize)
                    }
                    .accessibilityLabel("Next")
                    .disabled(track == nil || !player.canSkip)
                }
                // Mirrors the queue toggle on the opposite side so the play button stays
                // centred between them.
                HStack(spacing: 2) {
                    VolumeControl(iconSize: 12, controlSize: Self.controlSize)
                        .foregroundStyle(tintForeground.map { $0.opacity(0.85) } ?? Color.secondary)
                    AirPlayControl(controlSize: Self.controlSize, tint: tintForeground)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        onQueueToggleRequest()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                            .frame(width: Self.controlSize, height: Self.controlSize)
                            .contentShape(Rectangle())
                            .background {
                                RoundedRectangle(cornerRadius: playerControlCornerRadius)
                                    .fill(Color.primary.opacity(isQueueVisible ? 0.10 : 0))
                            }
                    }
                    .accessibilityLabel("Up Next")
                    .disabled(track == nil)
                    .foregroundStyle(tintForeground.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.primary))
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(PlayerControlButtonStyle())
            .foregroundStyle(tintForeground ?? Color.primary)

            if track != nil {
                MiniScrubber(tint: tintForeground)
            }
        }
    }
}

/// Inline queue rendered below the player in the mini window when the queue toggle
/// is on. Shares the main slide-over's QueueTable, so reordering, multi-select,
/// delete and dropping tracks in behave identically in both.
private struct InlineQueue: View {
    @Environment(PlayerService.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(NetworkMonitor.self) private var network

    @State private var scope: QueueScope = .upNext

    private var entries: [(originalIndex: Int, item: QueueItem)] {
        scope == .upNext ? player.upNextEntries : player.historyEntries
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                QueueScopeMenu(scope: $scope, font: .subheadline.weight(.semibold))
                Spacer()
                if !entries.isEmpty {
                    Button("Clear") {
                        scope == .upNext ? player.clearUpNext() : player.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(
                        scope == .upNext
                            ? "Remove everything after the current track"
                            : "Remove everything before the current track")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            QueueTable(
                items: entries.map(\.item),
                rowHeight: 44,
                showsDuration: false,
                // Translucent rather than solid white: the row keeps AppKit's emphasized
                // (white) text, which a solid white pill made invisible. A light wash
                // over the tint reads as selection and leaves the text legible.
                accent: player.tintsFromArtwork
                    ? Color.white.opacity(0.28)
                    : settings.resolvedAccentColor,
                actions: scope == .upNext
                    ? .standard(player: player, musicLibrary: musicLibrary, network: network)
                    : .history(player: player, musicLibrary: musicLibrary),
                // This panel's header pads 12, not the window's 16, and its shorter
                // rows need smaller artwork to keep an even gap above and below.
                horizontalInset: 12,
                artworkSize: 28,
                allowsEditing: scope == .upNext,
                emptyState: QueueEmptyState(
                    message: scope == .upNext
                        ? String(localized: "Nothing up next")
                        : String(localized: "Nothing played yet")
                )
            )
        }
        // Its own surface, so the queue reads as a separate region rather than more
        // of the transport block.
        .background(.quinary)
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

/// Forces the window dark while an artwork tint is showing.
///
/// The inline queue is an NSTableView, and AppKit resolves `labelColor` against the
/// window's appearance rather than SwiftUI's environment — so without this its rows stay
/// black text on a dark tint. The extractor caps brightness low enough that dark is
/// always the right answer here.
private struct WindowAppearance: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> AppearanceApplyingView { AppearanceApplyingView() }

    func updateNSView(_ nsView: AppearanceApplyingView, context: Context) {
        nsView.desiredAppearance = isDark ? NSAppearance(named: .darkAqua) : nil
    }
}

/// Puts the window into the appearance the content is drawn for.
///
/// Applied again when the view lands in a window, not only when the value changes: at
/// mount it has no window yet, and deferring the set to the next runloop turn is a race
/// it can lose. Losing it leaves the window on the system appearance while the content
/// draws as a dark surface — which is black label text on a blurred cover.
private final class AppearanceApplyingView: NSView {
    var desiredAppearance: NSAppearance? {
        didSet { applyToWindow() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyToWindow()
    }

    private func applyToWindow() {
        guard let window else { return }
        // By name: NSAppearance(named:) hands back a fresh instance each time, so
        // comparing the objects themselves would always differ and reassign.
        guard window.appearance?.name != desiredAppearance?.name else { return }
        window.appearance = desiredAppearance
    }
}

/// Reports pointer enter/exit for the whole mini player window.
///
/// `.activeAlways` on purpose: the point is to uncover the close button while the app is
/// in the background and you're just looking at the artwork.
private final class WindowHoverProbe: NSView {
    var onHoverChange: ((Bool) -> Void)?
    /// Just long enough to swallow a pointer clipping the window edge in passing.
    ///
    /// Deliberately short. AppKit drops a traffic light's hover colour the instant the
    /// pointer leaves, so anything longer leaves a grey button sitting there before the
    /// fade even starts — the wait is more conspicuous than the button was.
    var hideDelay: Duration = .milliseconds(400)

    private var trackingArea: NSTrackingArea?
    private var hideTask: Task<Void, Never>?

    /// Never takes a click — the transport, queue and drag gestures underneath do.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hideTask?.cancel()
        hideTask = nil
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hideTask?.cancel()
        let delay = hideDelay
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.onHoverChange?(false)
        }
    }
}

/// Raises the mini player above other applications' windows while the setting is on.
///
/// Only while Ondu itself is in the background, which is what "on top" is for.
/// AppKit's Cmd+` cycle won't step to a window it can't bring to the front, so a
/// permanently floating mini player silently killed window switching inside the app —
/// clicking the main window still worked, the shortcut didn't. Dropping back to the
/// normal level while the app is active costs nothing: both windows are ours, and
/// whichever you picked is the one in front.
///
/// Applied from the content rather than once at construction, so it takes effect the
/// moment the menu item is toggled and again whenever the window is reopened.
private struct MiniPlayerWindowLevel: NSViewRepresentable {
    let isFloating: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let level: NSWindow.Level = isFloating ? .floating : .normal
        if let window = nsView.window {
            if window.level != level { window.level = level }
            return
        }
        Task { @MainActor in
            guard let window = nsView.window, window.level != level else { return }
            window.level = level
        }
    }
}
#endif
