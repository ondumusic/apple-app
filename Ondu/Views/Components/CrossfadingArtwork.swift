import Nuke
import NukeUI
import SwiftUI

/// Album artwork that fades between covers instead of cutting.
///
/// The obvious approach — `.id(url)` on a `LazyImage` with a transition — looks worse
/// than no transition at all: changing identity throws away the view holding the loaded
/// image, so the fade runs from the old cover to an empty placeholder and the real image
/// appears after it finishes. This keeps the last loaded image on screen and only swaps
/// once the next one is actually decoded, so there is never a frame without a cover.
///
/// Rapid skipping is the case that shapes the rest. `.task(id:)` cancels the previous
/// load when the URL changes, so a slow response for a track you've already skipped past
/// can't arrive late and overwrite a newer one — hold next long enough and you keep the
/// cover you started from until the one you land on is ready.
struct CrossfadingArtwork: View {
    let url: URL?
    var size: ArtworkSize = .medium
    var fadeDuration: Double = 0.28

    @State private var shown: PlatformImage?
    /// What `shown` was loaded from, so the fade is driven by the image changing rather
    /// than by the request changing.
    @State private var shownURL: URL?

    var body: some View {
        ZStack {
            if let shown {
                Image(platform: shown)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(shownURL)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .animation(.easeInOut(duration: fadeDuration), value: shownURL)
        .task(id: url) { await load(url) }
    }

    private func load(_ url: URL?) async {
        guard let url else {
            shown = nil
            shownURL = nil
            return
        }
        guard url != shownURL else { return }

        let request = ImageRequest(url: url, processors: [.resize(width: CGFloat(size.pixels))])
        // Prefetched neighbours land here, which is the common case when skipping.
        if let cached = ImagePipeline.shared.cache[request]?.image {
            shown = cached
            shownURL = url
            return
        }
        guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
        // Cancellation already rules out a stale write, but the check is cheap and makes
        // the invariant local.
        guard !Task.isCancelled else { return }
        shown = image
        shownURL = url
    }
}

extension Image {
    fileprivate init(platform image: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}
