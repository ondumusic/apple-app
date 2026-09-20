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
final class MacOSAppDelegate: NSObject, NSApplicationDelegate {
    private var didClearLaunchFocus = false
    /// Strong refs so the KVO observers stay alive for the window's lifetime.
    private var titleObservers: [NSKeyValueObservation] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    private func configure(_ window: NSWindow) {
        hideTitle(on: window)
        clearLaunchFocus(in: window)
    }

    /// The toolbar carries the player, and a title beside it is what pushes the controls
    /// into the overflow menu at the minimum window width — measured: with the title
    /// shown, volume, AirPlay, queue and filter all land under `»` at 900pt. The sidebar
    /// selection says which view you're in, so the title earns none of that width.
    /// KVO rather than a one-shot: toolbar reconfigurations re-set it underneath us.
    private func hideTitle(on window: NSWindow) {
        // Both halves are needed: hiding alone doesn't stick, because SwiftUI re-sets
        // titleVisibility whenever it rebuilds the toolbar, and the string still
        // reserves its width.
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
                    musicLibrary.clearAll()
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
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Up Next") {
                    NotificationCenter.default.post(name: .toggleUpNext, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
            CommandGroup(after: .windowArrangement) {
                // Closing the window shouldn't strand the app: Cmd+N used to be the only
                // way back, and it's the shortcut for a *new* document, not this.
                ReopenMainWindowButton()
                Button("Mini Player") {
                    NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
                }
                // Cmd+M is Minimize on macOS and AppKit wins that fight; Music.app puts
                // the mini player on Cmd+Shift+M.
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Activity") {
                    NotificationCenter.default.post(name: .showDownloadActivity, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                Picker("Library Filter", selection: $libraryFilter) {
                    Text("All Music").tag(LibraryFilter.all)
                    Text("Downloaded").tag(LibraryFilter.downloaded)
                }
                .pickerStyle(.inline)
            }
            CommandMenu("Controls") {
                // No key equivalent here: a menu shortcut fires even while a text field
                // has focus, so Space would toggle playback mid-search. MacOSContentView
                // installs a local key monitor that can see the first responder instead.
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .togglePlayPause, object: nil)
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
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.quaternary.opacity(0.5))
                .frame(width: 240)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(height: 22)
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary.opacity(0.7))
                                .frame(height: 14)
                                .padding(.trailing, 60)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
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
