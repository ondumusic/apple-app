import SwiftUI

@main
struct MusicBoxApp: App {
    @State private var auth: AuthService

    init() {
        let auth = AuthService()
        auth.restoreSession()
        _auth = State(initialValue: auth)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn {
                    ContentView()
                } else {
                    NavigationStack {
                        LoginView()
                    }
                }
            }
            .environment(auth)
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
