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
    @State private var offlineStore = try! OfflineStore()
    @State private var downloadService: DownloadService?
    @State private var syncService: SyncService?

    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)

        let auth = AuthService()
        auth.restoreSession()
        let settings = SettingsStore()
        let offlineStore = try! OfflineStore()
        let musicLibrary = MusicLibrary(modelContainer: offlineStore.modelContainer)
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _offlineStore = State(initialValue: offlineStore)
        _musicLibrary = State(initialValue: musicLibrary)
        _player = State(initialValue: auth.apiService.map { PlayerService(api: $0, settings: settings, offlineStore: offlineStore) })
        _downloadService = State(initialValue: auth.apiService.map { DownloadService(api: $0, offlineStore: offlineStore, settings: settings) })
        _syncService = State(initialValue: auth.apiService.map { SyncService(api: $0, musicLibrary: musicLibrary) })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn, let syncService, let player {
                    ContentView()
                        .environment(musicLibrary)
                        .environment(settings)
                        .environment(offlineStore)
                        .environment(player)
                        .optionalEnvironment(downloadService)
                        .environment(syncService)
                        .optionalEnvironment(auth.apiService)
                } else if !auth.isLoggedIn {
                    NavigationStack {
                        LoginView()
                    }
                }
            }
            .environment(auth)
            .modelContainer(offlineStore.modelContainer)
            .onChange(of: auth.apiService.map(ObjectIdentifier.init)) { _, _ in
                if auth.apiService == nil {
                    SyncService.clearSyncState()
                    musicLibrary.clearAll()
                }
                player = auth.apiService.map { PlayerService(api: $0, settings: settings, offlineStore: offlineStore) }
                downloadService = auth.apiService.map { DownloadService(api: $0, offlineStore: offlineStore, settings: settings) }
                syncService = auth.apiService.map { SyncService(api: $0, musicLibrary: musicLibrary) }
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task {
                    await auth.validateSession()
                    await syncService?.syncIfNeeded()
                }
            }
            #endif
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                Task {
                    await auth.validateSession()
                    await syncService?.syncIfNeeded()
                }
            }
            #endif
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settings)
                .optionalEnvironment(syncService)
        }

        Window("Mini Player", id: "mini-player") {
            if let player {
                MacOSMiniPlayerView()
                    .environment(player)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
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
