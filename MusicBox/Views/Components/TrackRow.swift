import SwiftUI

struct TrackRow: View {
    let track: Track
    var showArtist = false
    var showNumber = true

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
    }
}
