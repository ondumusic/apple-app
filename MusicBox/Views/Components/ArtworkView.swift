import SwiftUI
import Nuke
import NukeUI

struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .processors([.resize(width: 300)])
        .priority(.normal)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
