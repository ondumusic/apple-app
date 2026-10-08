import SwiftUI

struct ArtistCard: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            ArtistArtworkView(artist: artist)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .lineLimit(1)

                if let count = artist.albumCount {
                    Text("^[\(count) album](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
