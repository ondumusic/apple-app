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

@main
struct MusicBoxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(BackgroundSessionDelegate.self) private var appDelegate
    #endif

    @State private var auth: AuthService
    @State private var musicLibrary: MusicLibrary
    @State private var settings = SettingsStore()
    @State private var player: PlayerService?
    /// Long-lived — survives login/logout cycles so the background URLSession identifier
    /// stays bound to a single instance (creating a second session with the same id crashes).
    @State private var downloadService: DownloadService
    @State private var syncService: SyncService?
    @State private var playbackCache: PlaybackCache
    @State private var networkMonitor = NetworkMonitor()
    @State private var searchHistory = SearchHistory()

    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)

        let auth = AuthService()
        auth.observeSessionExpiration()
        auth.restoreSession()
        let settings = SettingsStore()
        let musicLibrary = try! MusicLibrary()
        let playbackCache = PlaybackCache(settings: settings)
        let downloadService = DownloadService(musicLibrary: musicLibrary, settings: settings)
        if let api = auth.apiService {
            downloadService.configure(baseURL: api.baseURL, sessionToken: api.sessionToken)
        }
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _musicLibrary = State(initialValue: musicLibrary)
        _playbackCache = State(initialValue: playbackCache)
        _downloadService = State(initialValue: downloadService)
        _player = State(initialValue: auth.apiService.map { PlayerService(api: $0, settings: settings, musicLibrary: musicLibrary, playbackCache: playbackCache) })
        _syncService = State(initialValue: auth.apiService.map { SyncService(api: $0, musicLibrary: musicLibrary, settings: settings, downloadService: downloadService) })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn, let syncService, let player {
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
                } else if !auth.isLoggedIn {
                    NavigationStack {
                        LoginView()
                    }
                } else {
                    // auth.isLoggedIn but services not yet initialized
                    ProgressView()
                }
            }
            .environment(auth)
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
                } else {
                    SyncService.clearSyncState()
                    musicLibrary.clearAll()
                    downloadService.clearAuth()
                }
                player = auth.apiService.map { PlayerService(api: $0, settings: settings, musicLibrary: musicLibrary, playbackCache: playbackCache) }
                syncService = auth.apiService.map { SyncService(api: $0, musicLibrary: musicLibrary, settings: settings, downloadService: downloadService) }
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                playbackCache.flushMetadataIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if !auth.isLoggedIn {
                    // Retry restore — Keychain may have been inaccessible on prelaunch
                    auth.restoreSession()
                } else {
                    Task { await auth.validateSession() }
                }
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
                Task { await syncService?.syncIfNeeded() }
                downloadService.resumeOnForeground()
            }
            #endif
        }

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
}
