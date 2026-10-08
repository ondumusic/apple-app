import Foundation

/// One rendition of an album's artwork.
///
/// The server renders a set of square versions and never upscales, so a variant's
/// dimensions can be smaller than the size it nominally represents — a 300px cover has
/// no 640 variant larger than itself. That's why selection works off the actual `width`
/// rather than a name like "large".
nonisolated struct ArtworkVariant: Codable, Sendable, Hashable {
    var url: URL
    var width: Int
    var height: Int
}

extension Array where Element == ArtworkVariant {
    /// The largest variant, which is what the deprecated `artworkUrl` used to be.
    var largest: ArtworkVariant? { self.max(by: { $0.width < $1.width }) }

    /// The cheapest variant that still covers `pixels` across.
    ///
    /// Smallest-that-fits rather than nearest: going under means visibly resampling a
    /// cover up, while going over only costs bytes. When nothing is big enough the
    /// largest is the best available — the source image simply isn't that large.
    func covering(pixelWidth pixels: Int) -> ArtworkVariant? {
        let fitting = filter { $0.width >= pixels }
        return fitting.min(by: { $0.width < $1.width }) ?? largest
    }
}
