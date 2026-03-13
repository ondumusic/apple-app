import SwiftUI

struct TrackRow: View {
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network

    let track: Track
    var album: Album? = nil
    var artist: Artist? = nil
    var showArtist = false
    var showArtwork = false
    var showNumber = true
    var onTap: (() -> Void)? = nil

    private var isCurrentTrack: Bool {
        player.currentTrack?.id == track.id
    }

    private var artworkUrl: URL? {
        album?.artworkUrl ?? track.album?.artworkUrl
    }

    private var isAvailable: Bool {
        network.isOnline || track.isDownloaded
    }

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                ArtworkView(url: artworkUrl, cornerRadius: 4, thumbnailSize: 40)
                    .frame(width: 40, height: 40)
                    .opacity(isAvailable ? 1 : 0.4)
            }

            if showNumber {
                Group {
                    if isCurrentTrack {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    } else {
                        Text("\(track.number)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .foregroundStyle(isCurrentTrack ? AnyShapeStyle(.tint) : isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)

                if showArtist {
                    Text(track.artist.name)
                        .font(.caption)
                        .foregroundStyle(isAvailable ? .secondary : .tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.callout)
                .foregroundStyle(isAvailable ? .secondary : .tertiary)
                .monospacedDigit()
                .fixedSize()
                .frame(minWidth: 42, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    if track.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .offset(x: -46)
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isAvailable else { return }
            onTap?()
        }
        .contextMenu {
            TrackContextMenuItems(track: track, album: album, artist: artist)
        }
    }
}
