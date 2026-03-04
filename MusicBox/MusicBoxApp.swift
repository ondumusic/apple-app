import SwiftUI

@main
struct MusicBoxApp: App {
    @State private var auth: AuthService
    @State private var library: LibraryViewModel?
    @State private var settings = SettingsStore()
    @State private var player: PlayerService?

    init() {
        let auth = AuthService()
        auth.restoreSession()
        let settings = SettingsStore()
        _auth = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _library = State(initialValue: auth.apiService.map { LibraryViewModel(api: $0) })
        _player = State(initialValue: auth.apiService.map { PlayerService(api: $0, settings: settings) })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn, let library {
                    ContentView()
                        .environment(library)
                        .environment(settings)
                        .optionalEnvironment(player)
                } else {
                    NavigationStack {
                        LoginView()
                    }
                }
            }
            .environment(auth)
            .onChange(of: auth.apiService.map(ObjectIdentifier.init)) { _, _ in
                library = auth.apiService.map { LibraryViewModel(api: $0) }
                player = auth.apiService.map { PlayerService(api: $0, settings: settings) }
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await auth.validateSession() }
            }
            #endif
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                Task { await auth.validateSession() }
            }
            #endif
        }
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
}
