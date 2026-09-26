import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(SettingsStore.self) private var settings
    var onTap: () -> Void

    @State private var artworkColor: Color?
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let swipeThreshold: CGFloat = 50

    private var artworkURL: URL? {
        player.queue.indices.contains(player.effectiveIndex)
            ? player.queue[player.effectiveIndex].artworkURL : nil
    }

    var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                // Progress bar
                let tinted = settings.artworkTintedPlayer && artworkColor != nil
                GeometryReader { geo in
                    let fraction = player.duration > 0 ? player.progress / player.duration : 0
                    Rectangle()
                        .fill(tinted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tint))
                        .frame(width: geo.size.width * min(fraction, 1))
                }
                .frame(height: 2)
                .padding(.horizontal, 6)
                .background(tinted ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.quaternary))

                HStack(spacing: 10) {
                    ArtworkView(url: artworkURL, cornerRadius: 4, size: .thumbnail)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            if player.isBuffering {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(track.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                        }
                        if let error = player.playbackError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else {
                            Text(track.artist.name)
                                .font(.caption)
                                .foregroundStyle(tinted ? .white.opacity(0.7) : .secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Button { Haptics.light(); player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { Haptics.light(); player.skip() } label: {
                        Image(systemName: "forward.fill")
                            .font(.callout)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.canSkip)
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
                .offset(x: dragOffset)
                .opacity(1.0 - min(abs(dragOffset) / 120.0, 0.5))
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            // Only allow horizontal drags
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            isDragging = true

                            // Dampen the drag if action isn't available
                            let canDrag = value.translation.width > 0 ? player.canGoBack : player.canSkip
                            dragOffset = canDrag ? value.translation.width : value.translation.width * 0.2
                        }
                        .onEnded { value in
                            guard isDragging else {
                                dragOffset = 0
                                return
                            }
                            isDragging = false

                            if value.translation.width < -swipeThreshold && player.canSkip {
                                Haptics.light()
                                // Animate out, perform skip, animate in from opposite side
                                withAnimation(.easeIn(duration: 0.15)) {
                                    dragOffset = -300
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    player.skip()
                                    dragOffset = 300
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = 0
                                    }
                                }
                            } else if value.translation.width > swipeThreshold && player.canGoBack {
                                Haptics.light()
                                withAnimation(.easeIn(duration: 0.15)) {
                                    dragOffset = 300
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    player.back()
                                    dragOffset = -300
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = 0
                                    }
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
            .foregroundStyle(settings.artworkTintedPlayer && artworkColor != nil ? .white : .primary)
            .background {
                Group {
                    if settings.artworkTintedPlayer, let artworkColor {
                        artworkColor
                    } else {
                        #if os(iOS)
                        Color(.secondarySystemBackground)
                        #else
                        Color(nsColor: .windowBackgroundColor)
                        #endif
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: artworkColor != nil)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .task(id: "\(artworkURL?.absoluteString ?? ""):\(settings.artworkTintedPlayer)") {
                guard settings.artworkTintedPlayer else {
                    withAnimation(.easeInOut(duration: 0.5)) { artworkColor = nil }
                    return
                }
                let color = await ArtworkColorExtractor.extractColor(from: artworkURL, maxBrightness: 0.4)
                withAnimation(.easeInOut(duration: 0.5)) { artworkColor = color }
            }
        }
    }
}
