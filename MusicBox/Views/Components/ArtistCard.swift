import SwiftUI

struct ArtistCard: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.quaternary)

                Text(artist.name.prefix(1).uppercased())
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .lineLimit(1)

                if let count = artist.albumCount {
                    Text("\(count) \(count == 1 ? "album" : "albums")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
