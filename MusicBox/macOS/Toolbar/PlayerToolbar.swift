#if os(macOS)
import SwiftUI

/// Player content for the macOS window toolbar. Built as a set of ToolbarContent items
/// rather than one principal item — putting a complex interactive view (incl. a popover)
/// inside a single ToolbarItem.principal caused beachball/hang in earlier iterations.
struct PlayerToolbar: ToolbarContent {
    @Environment(PlayerService.self) private var player
    @Binding var showQueue: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            TransportButtons()
            NowPlayingLabel()
                .frame(minWidth: 260, idealWidth: 360)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .symbolVariant(player.isShuffled ? .none : .none)
                    .foregroundStyle(player.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .help(player.isShuffled ? "Disable Shuffle" : "Shuffle")
            .disabled(player.queue.isEmpty)

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIconName)
                    .foregroundStyle(player.repeatMode != .off ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .help(repeatHelp)
            .disabled(player.queue.isEmpty)

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .help("Queue")
            .disabled(player.currentTrack == nil)
        }
    }

    private var repeatIconName: String {
        switch player.repeatMode {
        case .off: "repeat"
        case .all: "repeat"
        case .one: "repeat.1"
        }
    }

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat All"
        case .one: "Repeat One"
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
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(track?.name ?? "Not Playing")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let track {
                        Text("—")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(track.artist.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                if track != nil {
                    ScrubberView()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if track != nil {
                ArtworkView(url: artworkURL, cornerRadius: 3)
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.tertiary)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
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

private struct ScrubberView: View {
    @Environment(PlayerService.self) private var player
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(format(time: isScrubbing ? scrubValue : player.progress))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : player.progress },
                    set: { newValue in
                        scrubValue = newValue
                        isScrubbing = true
                    }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: scrubValue)
                        isScrubbing = false
                    }
                }
            )
            .controlSize(.mini)
            Text(format(time: player.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .leading)
        }
    }

    private func format(time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
