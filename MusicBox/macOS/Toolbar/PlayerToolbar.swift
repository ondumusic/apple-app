#if os(macOS)
import SwiftUI

/// Player content for the macOS window toolbar. Built as a set of ToolbarContent items
/// rather than one principal item — putting a complex interactive view (incl. a popover)
/// inside a single ToolbarItem.principal caused beachball/hang in earlier iterations.
struct PlayerToolbar: ToolbarContent {
    @Environment(PlayerService.self) private var player
    @Binding var showQueue: Bool

    var body: some ToolbarContent {
        // Group transport + now-playing as adjacent items so the buttons sit right next
        // to the track label rather than getting pushed to opposite ends of the toolbar.
        ToolbarItemGroup(placement: .principal) {
            TransportButtons()
            NowPlayingLabel()
                .frame(minWidth: 220, idealWidth: 320)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .help("Queue")
            .disabled(player.currentTrack == nil)
        }
    }
}

private struct TransportButtons: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 4) {
            Button { player.back() } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!player.canGoBack || player.currentTrack == nil)
            .help("Previous")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(player.currentTrack == nil)
            .help(player.isPlaying ? "Pause" : "Play")

            Button { player.skip() } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!player.canSkip || player.currentTrack == nil)
            .help("Next")
        }
    }
}

private struct NowPlayingLabel: View {
    @Environment(PlayerService.self) private var player

    private var track: Track? { player.currentTrack }
    private var artworkURL: URL? {
        guard player.queue.indices.contains(player.effectiveIndex) else { return nil }
        return player.queue[player.effectiveIndex].artworkURL
    }

    var body: some View {
        HStack(spacing: 8) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(track?.name ?? "Not Playing")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let track {
                    Text(track.artist.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if track != nil {
                ArtworkView(url: artworkURL, cornerRadius: 3)
                    .frame(width: 22, height: 22)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tertiary)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .toggleMiniPlayer, object: nil)
        }
        .help("Open Mini Player")
    }
}
#endif
