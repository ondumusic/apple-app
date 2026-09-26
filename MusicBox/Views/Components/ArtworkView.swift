import SwiftUI
import Nuke
import NukeUI

/// How large a piece of artwork is going to be drawn.
///
/// Three buckets rather than a number per call site. Nuke keys its cache on the resize,
/// so asking for 320 in one view and 360 in another means two downloads, two decodes and
/// two cache entries for the same cover — snapping to a shared set keeps it to at most
/// three renditions per album. They're absolute pixels, chosen to cover the worst case
/// (an @3x phone), so callers never do scale arithmetic.
///
/// These are also what gets matched against the server's artwork variants, via
/// `[ArtworkVariant].covering(pixelWidth:)`.
nonisolated enum ArtworkSize {
    /// List rows and small covers, up to ~64pt.
    case thumbnail
    /// Grid covers and detail headers, up to ~200pt.
    case medium
    /// The players, where artwork is the subject: up to 540pt on the Mac, 300pt at @3x.
    case large

    var pixels: Int {
        switch self {
        case .thumbnail: 200
        case .medium: 600
        case .large: 1200
        }
    }
}

struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var size: ArtworkSize = .medium

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
        .processors([.resize(width: CGFloat(size.pixels))])
        // Rows scroll past in bulk and are the one place worth yielding the network to
        // whatever the user is actually looking at.
        .priority(size == .thumbnail ? .low : .normal)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
