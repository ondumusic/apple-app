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

    private var variant: ArtworkVariant? {
        artist.artwork.covering(pixelWidth: Int(size * 3))
    }

    var body: some View {
        Group {
            if let variant {
                CrossfadingArtwork(url: variant.url, size: .thumbnail)
            } else {
                ZStack {
                    Circle().fill(.quaternary)
                    Image(systemName: "music.mic")
                        .font(.system(size: size * 0.38))
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
