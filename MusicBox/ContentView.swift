import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        #if os(iOS)
        iOSRootView()
        #else
        macOSRootView()
        #endif
    }
}
