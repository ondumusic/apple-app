import SwiftUI

#if os(iOS)
struct NowPlayingBarModifier: ViewModifier {
    @Environment(PlayerService.self) private var player
    @State private var showFullPlayer = false
    @State private var barHeight: CGFloat = 60
    @State private var contentFrame: CGRect = .zero
    private let keyboard = KeyboardObserver.shared

    private var showBar: Bool { player.currentTrack != nil }

    func body(content: Content) -> some View {
        let keyboardOverlap = KeyboardAvoidance.overlap(
            contentFrame: contentFrame, keyboardFrame: keyboard.keyboardFrame
        )
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
            .padding(.bottom, keyboardOverlap)
            .animation(.easeOut(duration: keyboard.animationDuration), value: keyboardOverlap)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame = $0 }
            // Opt out of SwiftUI's automatic keyboard avoidance: it sometimes
            // fails to reset its inset when the keyboard dismisses during a
            // transition, leaving the layout permanently shrunk. The manual
            // padding above is driven by UIKit's keyboard notifications instead.
            .ignoresSafeArea(.keyboard)
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
