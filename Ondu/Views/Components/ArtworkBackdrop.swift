import Nuke
import NukeUI
import SwiftUI

/// PROTOTYPE — the artwork itself, blurred, as a player background.
///
/// The alternative is a gradient built from one extracted colour, which reduces a cover
/// to its average hue: fine for a monochrome sleeve, muddy for a busy one. Blurring keeps
/// the cover's own structure, which is what Apple's players do.
///
/// Fed a mid-size rendition rather than the full cover: blur hides detail, so the largest
/// variant is wasted here. Not the 200px thumbnail either — at the smaller radii a short
/// strip needs, upscaling 200px to window width is visibly soft.
///
/// The radius has to suit the region, not the image. At 44 in an 80pt-tall strip the blur
/// is wider than the view and everything collapses to a single colour.
struct ArtworkBackdrop: View {
    let url: URL?
    var blurRadius: CGFloat = 44
    /// Keeps white text legible over whatever the cover happens to be.
    var dimming: Double = 0.45

    var body: some View {
        CrossfadingArtwork(url: url, size: .medium)
            // Overscaled before blurring: a blur samples past the edges, and without
            // slack it pulls in transparency and vignettes the corners.
            .scaleEffect(1.4)
            .blur(radius: blurRadius, opaque: true)
            .overlay(Color.black.opacity(dimming))
            .clipped()
            .allowsHitTesting(false)
    }
}
