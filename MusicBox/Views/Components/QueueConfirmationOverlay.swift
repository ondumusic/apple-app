import SwiftUI

struct QueueConfirmationOverlay: ViewModifier {
    @Environment(PlayerService.self) private var player

    @State private var showing = false
    @State private var message = ""
    @State private var dismissTask: Task<Void, Never>?

    private var bottomPadding: CGFloat {
        #if os(iOS)
        player.currentTrack != nil ? 140 : 80
        #else
        80
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if showing {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: player.queueConfirmation) {
                guard let confirmation = player.queueConfirmation else { return }
                player.queueConfirmation = nil

                switch confirmation {
                case .playNext(let count):
                    message = count == 1 ? "Playing Next" : "Playing \(count) Songs Next"
                case .addedToQueue(let count):
                    message = count == 1 ? "Added to Queue" : "Added \(count) Songs to Queue"
                }

                dismissTask?.cancel()

                withAnimation(.easeOut(duration: 0.2)) {
                    showing = true
                }

                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.3)) {
                        showing = false
                    }
                }
            }
    }
}

extension View {
    func queueConfirmationOverlay() -> some View {
        modifier(QueueConfirmationOverlay())
    }
}
