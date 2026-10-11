import Foundation

/// Pages on the app's website that the app links to.
nonisolated enum SiteLinks {
    static let website = URL(string: "https://ondumusic.com")!
    static let serverSetup = URL(string: "https://ondumusic.com/setup.html")!
    /// App Review wants this reachable from inside the app, not only on the store listing.
    static let privacyPolicy = URL(string: "https://ondumusic.com/privacy.html")!
}
