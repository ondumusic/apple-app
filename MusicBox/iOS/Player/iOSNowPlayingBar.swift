import SwiftUI

#if os(iOS)
struct NowPlayingBarModifier: ViewModifier {
    @Environment(PlayerService.self) private var player
    @State private var showFullPlayer = false
    @State private var barHeight: CGFloat = 60

    private var showBar: Bool { player.currentTrack != nil }

    func body(content: Content) -> some View {
        content
            .padding(.bottom, showBar ? barHeight : 0)
            .overlay(alignment: .bottom) {
                if showBar {
                    MiniPlayerView {
                        showFullPlayer = true
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                }
            }
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(20)
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
