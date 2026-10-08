import SwiftUI

struct QueueConfirmationOverlay: ViewModifier {
    @Environment(PlayerService.self) private var player

    @State private var showing = false
    @State private var message: LocalizedStringResource = ""
    @State private var dismissTask: Task<Void, Never>?

    // macOS has nothing at the bottom of the window for a centred toast to relate to,
    // and bottom-centre toasts aren't a Mac idiom — anchor it under the toolbar instead,
    // near the queue button whose contents just changed.
    #if os(iOS)
    /// Clears the tab bar, and the mini player when it's showing.
    private var overlayPadding: CGFloat { player.currentTrack != nil ? 140 : 80 }
    private let overlayAlignment: Alignment = .bottom
    private let overlayEdge: Edge = .bottom
    private let trailingPadding: CGFloat = 0
    #else
    /// Under the player row, which from macOS 26 floats over the content this anchors to.
    @Environment(\.floatingChromeHeight) private var chromeHeight
    private var overlayPadding: CGFloat { chromeHeight + 12 }
    private let overlayAlignment: Alignment = .topTrailing
    private let overlayEdge: Edge = .top
    private let trailingPadding: CGFloat = 16
    #endif

    func body(content: Content) -> some View {
        content
            .overlay(alignment: overlayAlignment) {
                if showing {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(Edge.Set(overlayEdge), overlayPadding)
                        .padding(.trailing, trailingPadding)
                        .transition(.move(edge: overlayEdge).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: player.queueConfirmation) {
                guard let confirmation = player.queueConfirmation else { return }
                player.queueConfirmation = nil

                switch confirmation {
                case .playNext(let count):
                    message = count == 1
                        ? "Playing Next"
                        : "Playing ^[\(count) song](inflect: true) Next"
                case .addedToQueue(let count):
                    message = count == 1
                        ? "Added to Queue"
                        : "Added ^[\(count) song](inflect: true) to Queue"
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

    func replaceQueueConfirmation() -> some View {
        modifier(ReplaceQueueConfirmation())
    }
}

struct ReplaceQueueConfirmation: ViewModifier {
    @Environment(PlayerService.self) private var player

    func body(content: Content) -> some View {
        @Bindable var player = player
        content
            .alert("Replace Queue?", isPresented: $player.showReplaceQueueConfirmation) {
                // Replacing the queue isn't destructive — nothing is lost that the user
                // created — and it's the outcome they asked for, so it's the default.
                Button("Replace") { player.confirmPlay() }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { player.cancelPlay() }
            } message: {
                Text("This will replace your current queue and start new playback.")
            }
    }
}
