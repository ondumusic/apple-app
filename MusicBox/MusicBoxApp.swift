import SwiftUI
import SwiftData
import Nuke

#if os(iOS)
class BackgroundSessionDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == "com.musicbox.downloads" else {
            completionHandler()
            return
        }
        BackgroundSessionDelegate.pendingCompletionHandler = completionHandler
    }

    static var pendingCompletionHandler: (() -> Void)?
}
#endif

#if os(macOS)
extension NSApplication {
    /// Set during termination so the main window closing as part of quitting isn't
    /// recorded as the user having closed it.
    @MainActor static var isTerminatingForReal = false
    @MainActor var isTerminatingForReal: Bool { NSApplication.isTerminatingForReal }
}

final class MacOSAppDelegate: NSObject, NSApplicationDelegate {
    private var didClearLaunchFocus = false
    private var trackedMainWindows: Set<ObjectIdentifier> = []
    /// Strong refs so the KVO observers stay alive for the window's lifetime.
    private var titleObservers: [NSKeyValueObservation] = []
    private var spaceKeyMonitor: Any?
    /// Set at launch when the app should come back as mini-player-only. The Window scene
    /// always creates its window, so the main one is kept off-screen from the moment it
    /// exists rather than being shown and then closed — closing it is MacOSContentView's
    /// job, once the mini player is actually up.
    static var suppressesMainWindow = false

    func applicationWillTerminate(_ notification: Notification) {
        NSApplication.isTerminatingForReal = true
    }

    /// Set by the app so playback shortcuts keep working with the main window closed —
    /// they used to live in MacOSContentView, which unmounts with its window and took
    /// Space away from the mini player.
    var player: PlayerService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.suppressesMainWindow =
            UserDefaults.standard.bool(forKey: MiniPlayerWindowController.visibleDefaultsKey)
            && !UserDefaults.standard.bool(forKey: Self.mainWindowVisibleKey)
        if Self.suppressesMainWindow { scheduleMainWindowFallback() }
        installSpaceKeyMonitor()
        NotificationCenter.default.addObserver(
            forName: .togglePlayPause,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.togglePlayPause() }
        }
        for window in NSApp.windows {
            configure(window)
        }
        for window in NSApp.windows {
            configure(window)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.configure(window)
        }
    }

    /// Space toggles playback, but not while a text field has focus — which is why this
    /// is a key monitor and not a menu key equivalent: a menu shortcut fires regardless
    /// of the first responder and would toggle playback mid-search.
    private func installSpaceKeyMonitor() {
        guard spaceKeyMonitor == nil else { return }
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let spaceKeyCode: UInt16 = 49
            guard event.keyCode == spaceKeyCode, modifiers.isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            MainActor.assumeIsolated { self?.player?.togglePlayPause() }
            return nil
        }
    }

    /// The library window, as opposed to the mini player, Settings or Activity. SwiftUI
    /// stamps a `Window` scene's id onto its NSWindow, which is the only reliable way to
    /// tell them apart — stripping the chrome off Settings took its tab bar with it,
    /// since SwiftUI renders a Settings TabView's tabs as an NSToolbar.
    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == mainWindowSceneId
    }

    static let mainWindowSceneId = "main"

    private func isMainWindow(_ window: NSWindow) -> Bool { Self.isMainWindow(window) }

    /// Whether the main window was open when the app last quit. Closing with only the
    /// mini player showing should come back the same way.
    static let mainWindowVisibleKey = "MainWindowVisible"

    private func configure(_ window: NSWindow) {
        makeChromeless(window)
        clearLaunchFocus(in: window)
        if Self.suppressesMainWindow, isMainWindow(window) {
            window.orderOut(nil)
            return
        }
        trackMainWindowVisibility(window)
    }

    /// If the mini player never arrives — a login is due, or session restore failed —
    /// the hidden main window is all there is, so put it back rather than leave the app
    /// running with nothing on screen.
    private func scheduleMainWindowFallback() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MainActor.assumeIsolated {
                guard Self.suppressesMainWindow else { return }
                Self.suppressesMainWindow = false
                let miniIsUp = NSApp.windows.contains {
                    $0.identifier == MiniPlayerWindowController.windowIdentifier && $0.isVisible
                }
                guard !miniIsUp else { return }
                NSApp.windows.first(where: Self.isMainWindow)?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func trackMainWindowVisibility(_ window: NSWindow) {
        guard isMainWindow(window) else { return }
        UserDefaults.standard.set(true, forKey: Self.mainWindowVisibleKey)
        guard !trackedMainWindows.contains(ObjectIdentifier(window)) else { return }
        trackedMainWindows.insert(ObjectIdentifier(window))
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard !NSApp.isTerminatingForReal else { return }
                UserDefaults.standard.set(false, forKey: Self.mainWindowVisibleKey)
            }
        }
    }

    /// Music.app's window has no toolbar at all — inspected: its window holds exactly
    /// one split view and three traffic lights, and the player controls are ordinary
    /// subviews inside that split view. So the content runs to the top of the window and
    /// the traffic lights float over it.
    ///
    /// A toolbar is what forces an overflow model on the player, and what reserves a
    /// titlebar strip the content then has to sit below. Refusing one is the whole point.
    /// KVO on the title because SwiftUI re-sets it whenever it rebuilds.
    private func makeChromeless(_ window: NSWindow) {
        guard isMainWindow(window) else { return }
        window.styleMask.insert(.fullSizeContentView)
        // Dropping the toolbar also dropped the window out of the zoom/full-screen
        // machinery, which is what took "Enter Full Screen" off the View menu.
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        if !window.title.isEmpty { window.title = "" }
        window.titleVisibility = .hidden
        let observation = window.observe(\.title, options: [.new]) { window, _ in
            if !window.title.isEmpty { window.title = "" }
            window.titleVisibility = .hidden
        }
        titleObservers.append(observation)
    }

    private func clearLaunchFocus(in window: NSWindow) {
        // Clear focus once at launch so the system doesn't park keyboard focus on the
        // sidebar's search field. NSText (the field editor for any text input) is what
        // actually shows up as firstResponder, not the NSSearchField itself.
        if !didClearLaunchFocus {
            didClearLaunchFocus = true
            if window.firstResponder is NSText || window.firstResponder is NSTextField {
                window.makeFirstResponder(nil)
                #if DEBUG
                print("[focus] cleared launch firstResponder")
                #endif
            }
            // Subsequent didBecomeMain notifications keep whatever the user has focused.
        }
    }
}
#endif

@main
struct MusicBoxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BackgroundSessionDelegate.self) private var appDelegate
    #endif
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacOSAppDelegate.self) private var macAppDelegate
    #endif

    @State private var auth: AuthService
    @State private var musicLibrary: MusicLibrary
    @State private var settings = SettingsStore()
    @State private var player: PlayerService?
    /// Long-lived — survives login/logout cycles so the background URLSession identifier
    /// stays bound to a single instance (creating a second session with the same id crashes).
    @State private var downloadService: DownloadService
    @State private var syncService: SyncService?
    @State private var outboxService: OutboxService?
    @State private var playlistController: PlaylistController?
    @State private var playbackCache: PlaybackCache
    @State private var networkMonitor = NetworkMonitor()
    @State private var searchHistory = SearchHistory()
    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all

    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        #if os(macOS)
        // Disable window-tab grouping (the macOS feature that lets multiple windows
        // join into Safari-style tabs). MusicBox is single-window.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif

        let auth = AuthService()
        auth.observeSessionExpiration()
        let settings = SettingsStore()
        let musicLibrary = try! MusicLibrary()
        let playbackCache = PlaybackCache(settings: settings)
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _musicLibrary = State(initialValue: musicLibrary)
        _playbackCache = State(initialValue: playbackCache)
        _downloadService = State(initialValue: DownloadService(musicLibrary: musicLibrary, settings: settings))
        // The session is restored in a .task, so there's no API service yet — the
        // apiService onChange builds the rest once it lands.
    }

    @ViewBuilder
    private var rootView: some View {
            Group {
                if auth.isRestoringSession {
                    LaunchPlaceholder()
                        .transition(.opacity)
                } else if auth.isLoggedIn, let syncService, let player {
                    ContentView()
                        .environment(musicLibrary)
                        .environment(settings)
                        .environment(player)
                        .environment(playbackCache)
                        .environment(downloadService)
                        .environment(syncService)
                        .environment(networkMonitor)
                        .environment(searchHistory)
                        .optionalEnvironment(auth.apiService)
                        .optionalEnvironment(playlistController)
                        .optionalEnvironment(outboxService)
                } else if !auth.isLoggedIn {
                    NavigationStack {
                        LoginView()
                    }
                } else {
                    // Logged in, services still coming up — same placeholder rather than a
                    // bare spinner, so the window doesn't change shape twice.
                    LaunchPlaceholder()
                }
            }
            .environment(auth)
            .animation(.easeOut(duration: 0.18), value: auth.isRestoringSession)
            .task { await auth.beginSessionRestore() }
            #if os(macOS)
            .onChange(of: player == nil, initial: true) { _, _ in macAppDelegate.player = player }
            #endif
            .accentColor(settings.resolvedAccentColor)
            .onChange(of: settings.hapticsEnabled, initial: true) { _, enabled in
                Haptics.isEnabled = enabled
            }
            .modelContainer(musicLibrary.modelContainer)
            .onChange(of: auth.apiService.map(ObjectIdentifier.init)) { _, _ in
                if let api = auth.apiService {
                    downloadService.configure(baseURL: api.baseURL, sessionToken: api.sessionToken)
                    // If downloads were paused due to a prior 401, let them resume under the new token.
                    if downloadService.isPaused { downloadService.resumeAll() }
                    // Re-auth mints a new APIService — hand it to the running player rather than
                    // rebuilding one, which would drop the queue and stop playback mid-track.
                    if let player {
                        player.update(api: api)
                    } else {
                        player = PlayerService(api: api, settings: settings, musicLibrary: musicLibrary, playbackCache: playbackCache)
                    }
                } else {
                    SyncService.clearSyncState()
                    musicLibrary.clearAll(includingDownloads: true)
                    downloadService.clearAuth()
                    PlaybackStateStore.clearPersisted()
                    player = nil
                }
                let newOutbox = auth.apiService.map { OutboxService(musicLibrary: musicLibrary, api: $0) }
                outboxService = newOutbox
                syncService = auth.apiService.map { SyncService(api: $0, musicLibrary: musicLibrary, settings: settings, downloadService: downloadService, outbox: newOutbox) }
                playlistController = newOutbox.map { PlaylistController(musicLibrary: musicLibrary, outbox: $0, downloadService: downloadService) }
                if newOutbox != nil {
                    Task { await newOutbox?.flush() }
                }
            }
            .onChange(of: networkMonitor.isOnline) { _, online in
                if online {
                    Task { await outboxService?.flush() }
                }
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                playbackCache.flushMetadataIfNeeded()
                player?.savePlaybackState()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if !auth.isLoggedIn {
                    // Retry restore — Keychain may have been inaccessible on prelaunch
                    Task { await auth.restoreSession() }
                } else {
                    Task { await auth.validateSession() }
                }
                Task { await outboxService?.flush() }
                Task { await syncService?.syncIfNeeded() }
                downloadService.resumeOnForeground()
            }
            #endif
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                playbackCache.flushMetadataIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                Task { await auth.validateSession() }
                Task { await outboxService?.flush() }
                Task { await syncService?.syncIfNeeded() }
                downloadService.resumeOnForeground()
            }
            #endif
    }

    var body: some Scene {
        // A single Window rather than a WindowGroup: Cmd+N was spawning duplicate
        // main windows, and a second one has no meaning here. Window also gives the
        // Window menu an entry to bring it back after closing.
        #if os(macOS)
        Window("MusicBox", id: "main") {
            rootView
        }
        // No toolbar at all, and no titlebar strip reserved — the window Music.app has.
        // Doing this by hand with fullSizeContentView plus ignoresSafeArea either left a
        // 28pt band above the player row or grew the content past the window's top edge
        // and clipped it.
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()
        .commands {
            // .commandsRemoved() above strips this group wholesale, which took Cut,
            // Copy, Paste and Select All with it — Cmd+A in any list, and Cmd+C/V in the
            // sidebar's rename field. Standard first-responder forwarding puts them back.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x", modifiers: .command)
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    .keyboardShortcut("v", modifiers: .command)
                Divider()
                Button("Select All") { NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                // Closing the window shouldn't strand the app: Cmd+N used to be the only
                // way back, and it's the shortcut for a *new* document, not this.
                // Music.app puts its main window on Cmd+0.
                ReopenMainWindowButton()
                // Music.app's split: one command shows the mini player beside the main
                // window, another swaps to it. Both shortcuts are theirs.
                Button("Mini Player") {
                    NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
                Button("Switch to Mini Player") {
                    NotificationCenter.default.post(name: .switchToMiniPlayer, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Toggle("Keep Mini Player on Top", isOn: Binding(
                    get: { settings.miniPlayerAlwaysOnTop },
                    set: { settings.miniPlayerAlwaysOnTop = $0 }
                ))
                Button("Activity") {
                    NotificationCenter.default.post(name: .showDownloadActivity, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .newItem) {
                Button("New Playlist") {
                    NotificationCenter.default.post(name: .newPlaylistRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Toggle("Downloaded Only", isOn: Binding(
                    get: { libraryFilter == .downloaded },
                    set: { libraryFilter = $0 ? .downloaded : .all }
                ))
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Up Next") {
                    NotificationCenter.default.post(name: .toggleUpNext, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
                Divider()
                // Music.app reaches its library sections through the sidebar alone, but
                // it has no equivalent of these four fixed ones — numbering them is the
                // ordinary Mac idiom for a fixed set of views.
                ForEach(Array(SidebarCategory.allCases.enumerated()), id: \.element) { index, category in
                    Button(category.title) {
                        NotificationCenter.default.post(name: .selectLibrarySection, object: category)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
            }
            CommandMenu("Controls") {
                // No key equivalent on Play / Pause: a menu shortcut fires even while a
                // text field has focus, so Space would toggle playback mid-search. The
                // app delegate's key monitor can see the first responder and does it
                // properly — the cost is that the menu can't advertise the shortcut.
                Button(player?.isPlaying == true ? "Pause" : "Play") {
                    player?.togglePlayPause()
                }
                .disabled(player?.currentTrack == nil)

                Button("Next Track") { player?.skip() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(player?.canSkip != true)
                // Not `canGoBack`: it reads `progress` to decide whether Back restarts
                // the track, which makes this whole menu depend on a value that ticks
                // twice a second — SwiftUI rebuilds the main menu on the dependency
                // changing, not on the Bool changing, so a menu could be torn down and
                // re-presented while open. Back always does something with a track
                // loaded, so that's the honest condition anyway.
                Button("Previous Track") { player?.back() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(player?.currentTrack == nil)

                Button("Back") {
                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)
                Button("Go to Current Song") {
                    MainWindowNavigation.request(.goToCurrentSong)
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(player?.currentTrack == nil)

                Divider()

                Button("Increase Volume") {
                    player?.volume = min(1, (player?.volume ?? 0) + 0.1)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Decrease Volume") {
                    player?.volume = max(0, (player?.volume ?? 0) - 0.1)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Toggle("Shuffle", isOn: Binding(
                    get: { player?.isShuffled ?? false },
                    set: { _ in player?.toggleShuffle() }
                ))
                .disabled(player?.queue.isEmpty != false)

                Picker("Repeat", selection: Binding(
                    get: { player?.repeatMode ?? .off },
                    set: { mode in
                        guard let player else { return }
                        // cycleRepeatMode is the only writer that keeps SettingsStore and
                        // the gapless state in step, so step to the chosen mode rather
                        // than assigning it.
                        while player.repeatMode != mode { player.cycleRepeatMode() }
                    }
                )) {
                    Text("Off").tag(RepeatMode.off)
                    Text("All").tag(RepeatMode.all)
                    Text("One").tag(RepeatMode.one)
                }
            }
        }

        Window("Activity", id: "activity") {
            DownloadActivityView()
                .environment(downloadService)
                .environment(networkMonitor)
        }
        .defaultSize(width: 520, height: 340)
        .windowResizability(.contentMinSize)
        .commandsRemoved()
        #else
        WindowGroup {
            rootView
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(auth)
                .environment(settings)
                .environment(playbackCache)
                .optionalEnvironment(syncService)
        }

        #endif
    }
}

extension View {
    @ViewBuilder
    func optionalEnvironment(_ player: PlayerService?) -> some View {
        if let player {
            self.environment(player)
        } else {
            self
        }
    }

    @ViewBuilder
    func optionalEnvironment(_ service: DownloadService?) -> some View {
        if let service {
            self.environment(service)
        } else {
            self
        }
    }

    @ViewBuilder
    func optionalEnvironment(_ api: APIService?) -> some View {
        if let api {
            self.environment(api)
        } else {
            self
        }
    }

    @ViewBuilder
    func optionalEnvironment(_ sync: SyncService?) -> some View {
        if let sync {
            self.environment(sync)
        } else {
            self
        }
    }

    @ViewBuilder
    func optionalEnvironment(_ controller: PlaylistController?) -> some View {
        if let controller {
            self.environment(controller)
        } else {
            self
        }
    }

    @ViewBuilder
    func optionalEnvironment(_ outbox: OutboxService?) -> some View {
        if let outbox {
            self.environment(outbox)
        } else {
            self
        }
    }
}


#if os(macOS)
/// Brings the single main window back after it's been closed. Lives in a View so it can
/// reach openWindow, which isn't available on the App type itself.
private struct ReopenMainWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("MusicBox Window") {
            openWindow(id: "main")
        }
        .keyboardShortcut("0", modifiers: .command)
    }
}
#endif

#if os(macOS)
/// Stands in for the window's chrome while the session restores and services come up.
/// An empty window reads as a hang; the app's own shape reads as loading.
private struct LaunchPlaceholder: View {
    /// The real sidebar's width, so the placeholder doesn't jump sideways when the
    /// window loads with a sidebar the user has resized.
    @AppStorage("macSidebarWidth") private var sidebarWidth: Double = 240

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(width: sidebarWidth)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Stands in for the search field, at the position and size the
                        // real one has — 52pt down to clear the traffic lights, 28 tall,
                        // inset 10. It was starting at 14 with a 22pt bar, so the whole
                        // sidebar visibly dropped into place when the window loaded.
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(height: 28)
                            .padding(.horizontal, 10)

                        // Clears the field, its 6pt gap and the first section header.
                        Spacer().frame(height: 40)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary.opacity(0.7))
                                    .frame(height: 14)
                                    .padding(.trailing, 60)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.top, 52)
                }
            Divider()
            Rectangle().fill(.background)
        }
        .ignoresSafeArea()
    }
}
#else
private struct LaunchPlaceholder: View {
    var body: some View {
        Rectangle().fill(.background).ignoresSafeArea()
    }
}
#endif
