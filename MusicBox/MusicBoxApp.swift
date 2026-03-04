import SwiftUI

@main
struct MusicBoxApp: App {
    @State private var auth: AuthService
    @State private var library: LibraryViewModel?

    init() {
        let auth = AuthService()
        auth.restoreSession()
        _auth = State(initialValue: auth)
        _library = State(initialValue: auth.apiService.map { LibraryViewModel(api: $0) })
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn, let library {
                    ContentView()
                        .environment(library)
                } else {
                    NavigationStack {
                        LoginView()
                    }
                }
            }
            .environment(auth)
            .onChange(of: auth.apiService.map(ObjectIdentifier.init)) { _, _ in
                library = auth.apiService.map { LibraryViewModel(api: $0) }
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
