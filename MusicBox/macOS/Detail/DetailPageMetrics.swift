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
    static let horizontalInset = Spacing.page
    static let topInset = Spacing.page
    /// Less under the block than above it: the track list starts immediately below,
    /// where above it there's only the header strip.
    static let bottomInset = Spacing.block
    static let artworkSize: CGFloat = 180

    /// A track row. Tall enough that a long title can take a second line rather than
    /// truncate — which is what Music.app allows. 28, 32 and 36 were each too tight for
    /// the two lines they were letting through. Short titles just centre in it.
    static let trackRowHeight: CGFloat = 44
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
        HStack(spacing: Spacing.related) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
            }
            Button(action: onShuffle) {
                Label("Shuffle", systemImage: "shuffle")
            }
        }
        .buttonStyle(AccentActionButtonStyle(accent: accent))
        .disabled(!isEnabled)
    }
}

/// Filled accent, pill-shaped, with metrics we set.
///
/// `.borderedProminent` can't be a pill — `buttonBorderShape(.capsule)` silently
/// downgrades it back to `.bordered` — and its own padding is what sat the label off
/// centre. Doing the fill ourselves also lets the round download button beside these
/// match them exactly rather than being a different control that happens to be nearby.
struct AccentActionButtonStyle: ButtonStyle {
    let accent: Color
    /// A circle of the same height, for icon-only actions in the same group.
    var isCircular = false

    static let height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        Fill(configuration: configuration, accent: accent, isCircular: isCircular)
    }

    private struct Fill: View {
        let configuration: Configuration
        let accent: Color
        let isCircular: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                // Centred in the shape rather than padded from the text's own box: the
                // label's baseline and the capsule's centre are not the same thing, and
                // padding alone left it sitting high.
                .frame(height: AccentActionButtonStyle.height)
                .frame(minWidth: isCircular ? AccentActionButtonStyle.height : 0)
                .padding(.horizontal, isCircular ? 0 : 14)
                .background(Capsule().fill(accent))
                .opacity(opacity)
                .contentShape(Capsule())
        }

        private var opacity: Double {
            guard isEnabled else { return 0.4 }
            return configuration.isPressed ? 0.75 : 1
        }
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
    var accent: Color? = nil
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            switch state {
            case .downloading:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            case .notDownloaded:
                Image(systemName: "arrow.down")
            case .downloaded:
                Image(systemName: "checkmark")
            }
        }
        .modifier(DownloadButtonStyling(accent: accent))
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

/// Beside the page's Play and Shuffle it joins them: same height, same fill, a circle
/// instead of a pill. On its own — an album section header inside the artist page — it
/// stays a plain bordered circle, because a row of accent-filled buttons repeated down
/// the page would shout.
private struct DownloadButtonStyling: ViewModifier {
    let accent: Color?

    func body(content: Content) -> some View {
        if let accent {
            content.buttonStyle(AccentActionButtonStyle(accent: accent, isCircular: true))
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
    }
}

#endif
