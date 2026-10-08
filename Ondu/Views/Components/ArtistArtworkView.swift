import SwiftUI

/// An artist, as a circle.
///
/// Circular because that's what tells you at a glance that this is a person rather than a
/// record — albums are square everywhere else in the app. The server keeps the uploaded
/// image's aspect ratio and says to crop it however we show artists, so the crop is ours
/// to make and this is it.
///
/// Without artwork it's the glyph the list has always shown. Initials were the
/// alternative, and they read as noise beside real photographs: a per-artist colour and
/// letter claim to say something where one quiet shape says "no picture" and gets out of
/// the way. It's also what Music.app does.
struct ArtistArtworkView: View {
    let artist: Artist
    var size: CGFloat = 44

    /// One rendition for every size, resized locally, as albums do. Picking a variant per
    /// size would be fewer bytes for someone who only ever scrolls the list, but two
    /// downloads for anyone who opens the artist — which is most of the reason to click
    /// an artist at all.
    private var variant: ArtworkVariant? {
        artist.artwork.covering(pixelWidth: ArtworkSize.medium.pixels)
    }

    var body: some View {
        Group {
            if let variant {
                // ArtworkView, not CrossfadingArtwork: that one exists for the players,
                // where a track change should dissolve. Here it meant every artist began
                // as a glyph and faded in, which looks like nothing is cached — and
                // nowhere else in the app does artwork fade.
                ArtworkView(url: variant.url, cornerRadius: 0,
                            size: size > 64 ? .medium : .thumbnail)
            } else {
                ZStack {
                    Circle().fill(.quaternary)
                    Image(systemName: "music.mic")
                        // Capped rather than purely proportional: a mic scaled to 38% of
                        // a 96pt circle is a badge, where in a 28pt row it's a hint.
                        .font(.system(size: min(size * 0.38, 26)))
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
