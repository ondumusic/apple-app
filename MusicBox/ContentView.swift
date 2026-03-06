import SwiftUI

extension Notification.Name {
    static let scrollToTop = Notification.Name("MusicBox.scrollToTop")
    static let navigateToArtist = Notification.Name("MusicBox.navigateToArtist")
    static let navigateToAlbum = Notification.Name("MusicBox.navigateToAlbum")
}

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
