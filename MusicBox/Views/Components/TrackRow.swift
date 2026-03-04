import SwiftUI

struct TrackRow: View {
    @Environment(PlayerService.self) private var player

    let track: Track
    var showArtist = false
    var showNumber = true
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if showNumber {
                Text("\(track.number)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .lineLimit(1)

                if showArtist {
                    Text(track.artist.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            Button {
                player.playNext(tracks: [track])
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                player.addToEnd(tracks: [track])
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
        }
    }
}
