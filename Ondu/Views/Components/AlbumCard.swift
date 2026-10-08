import SwiftUI

struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: album.artworkUrl)
                .aspectRatio(1, contentMode: .fit)
                // Pale covers (the White Album is the obvious one) otherwise dissolve
                // into the page — grids sit on a light background on both platforms.
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }

            Text(album.name)
                .font(.callout)
                .lineLimit(1)

            Text(album.releaseYear.map(String.init) ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
