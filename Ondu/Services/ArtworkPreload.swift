import Foundation

/// When to preload the artwork a sync brought in. A first sync preloads the whole
/// library's covers — hundreds of megabytes on a large one — which on mobile data is a
/// bill nobody asked for. Browsing loads covers as they come on screen anyway, so the
/// preload is what waits.
nonisolated enum ArtworkPreload {
    enum Decision: Equatable {
        case now
        /// Hold until the network is neither mobile data nor Low Data Mode.
        case later
        /// Leave it to browsing.
        case never
    }

    /// New albums from an everyday sync: a few megabytes at most, worth having instant.
    static let smallBatch = 20

    static func decision(count: Int, isExpensive: Bool, isConstrained: Bool) -> Decision {
        if count <= smallBatch {
            // Low Data Mode is the user asking apps to hold back, so even a small batch waits
            // for browsing.
            return isConstrained ? .never : .now
        }
        return isExpensive || isConstrained ? .later : .now
    }
}
