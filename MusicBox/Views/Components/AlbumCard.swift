import SwiftUI

struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: album.artworkUrl)
                .aspectRatio(1, contentMode: .fit)

            Text(album.name)
                .font(.callout)
                .lineLimit(1)

            Text(album.releaseYear.map(String.init) ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
