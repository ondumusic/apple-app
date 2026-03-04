import SwiftUI

#if os(iOS)
struct NowPlayingBarModifier: ViewModifier {
    @Environment(PlayerService.self) private var player
    @State private var showFullPlayer = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if player.currentTrack != nil {
                    MiniPlayerView {
                        showFullPlayer = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
    }
}
#endif

extension View {
    func nowPlayingBar() -> some View {
        #if os(iOS)
        modifier(NowPlayingBarModifier())
        #else
        self
        #endif
    }
}
