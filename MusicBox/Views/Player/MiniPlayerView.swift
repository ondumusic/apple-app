import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(SettingsStore.self) private var settings
    var onTap: () -> Void

    @State private var artworkColor: Color?

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
                .background(tinted ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(.quaternary))

                HStack(spacing: 10) {
                    ArtworkView(url: artworkURL, cornerRadius: 4, thumbnailSize: 36)
                        .frame(width: 40, height: 40)
                        .id(player.currentTrack?.id)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: player.currentTrack?.id)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(track.artist.name)
                            .font(.caption)
                            .foregroundStyle(tinted ? .white.opacity(0.7) : .secondary)
                            .lineLimit(1)
                    }
                    .id(player.currentTrack?.id)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: player.currentTrack?.id)

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
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
            }
            .foregroundStyle(settings.artworkTintedPlayer && artworkColor != nil ? .white : .primary)
            .background {
                Group {
                    if settings.artworkTintedPlayer, let artworkColor {
                        artworkColor
                    } else {
                        Color(.secondarySystemBackground)
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
