import SwiftUI

@Observable
final class SettingsStore {
    var crossfadeDuration: Double {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }

    var maxConcurrentDownloads: Int {
        didSet { UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads") }
    }

    var isShuffled: Bool {
        didSet { UserDefaults.standard.set(isShuffled, forKey: "isShuffled") }
    }

    var repeatMode: RepeatMode {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") }
    }

    /// Maximum playback cache size in bytes. 0 means unlimited.
    var playbackCacheLimit: Int64 {
        didSet { UserDefaults.standard.set(playbackCacheLimit, forKey: "playbackCacheLimit") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.crossfadeDuration = defaults.object(forKey: "crossfadeDuration") as? Double ?? 1.0
        self.maxConcurrentDownloads = defaults.object(forKey: "maxConcurrentDownloads") as? Int ?? 3
        self.isShuffled = defaults.bool(forKey: "isShuffled")
        self.repeatMode = RepeatMode(rawValue: defaults.string(forKey: "repeatMode") ?? "") ?? .off
        self.playbackCacheLimit = defaults.object(forKey: "playbackCacheLimit") as? Int64 ?? (2 * 1024 * 1024 * 1024) // 2 GB default
    }
}
