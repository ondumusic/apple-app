#if os(macOS)
import SwiftUI

/// The numbers the album, artist and playlist pages share.
///
/// They used to each carry their own: three horizontal insets, two separator glyphs,
/// three shapes of Play button, and four row heights for the same single line of track.
/// None of that was decided — it accumulated.
enum DetailPageMetrics {
    /// Matches `AlbumsGridViewController.sectionInset`, so a cover doesn't step sideways
    /// when you open the album it belongs to.
    static let horizontalInset: CGFloat = 20
    static let topInset: CGFloat = 20
    static let bottomInset: CGFloat = 18
    static let artworkSize: CGFloat = 180

    /// One line of track: title, maybe a number, a duration.
    static let trackRowHeight: CGFloat = 28
    /// Two lines: a title with the artist stacked underneath. 40 clipped the pair
    /// against the selection pill; this is the height that doesn't.
    static let trackRowHeightTwoLine: CGFloat = 48
}

/// "2013 · 12 songs · 1 hr 8 min". One separator, one style, built once — the artist
/// page used a bullet where everything else used a middle dot.
struct DetailMetadataLine: View {
    let parts: [String]

    var body: some View {
        Text(parts.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// A page's primary actions. Music.app makes these the loudest thing on the page and
/// labels them; ours were quiet bordered buttons, and only one of the three pages
/// bothered with the labels.
struct PlayShuffleButtons: View {
    let accent: Color
    let onPlay: () -> Void
    let onShuffle: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
            }
            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
            }
        }
        .tint(accent)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}
/// What a page's download control looks like in each of its three states.
///
/// There were three of these: two variants of `arrow.down.circle` and a bordered
/// `arrow.down`, each with its own spinner treatment. The glyph carries the state, so
/// the only thing a caller decides is what the button does.
struct DownloadStateButton: View {
    enum State {
        case notDownloaded
        case downloading
        case downloaded
    }

    let state: State
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            switch state {
            case .downloading:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
            case .downloaded:
                Image(systemName: "arrow.down.circle.fill")
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!isEnabled)
        .help(helpText)
    }

    private var helpText: LocalizedStringResource {
        switch state {
        case .notDownloaded: "Download"
        case .downloading: "Cancel Download"
        case .downloaded: "Remove Download"
        }
    }
}
#endif
