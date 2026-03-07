import SwiftUI
import Nuke
import NukeUI

struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var thumbnailSize: CGFloat? = nil

    var body: some View {
        let resizeWidth = thumbnailSize.map { $0 * 2 } ?? 300

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
        .processors([.resize(width: resizeWidth)])
        .priority(thumbnailSize != nil ? .low : .normal)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
