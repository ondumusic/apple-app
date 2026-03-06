import SwiftUI

@Observable
final class SettingsStore {
    var crossfadeDuration: Double {
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }

    var maxConcurrentDownloads: Int {
        didSet { UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.crossfadeDuration = defaults.object(forKey: "crossfadeDuration") as? Double ?? 1.0
        self.maxConcurrentDownloads = defaults.object(forKey: "maxConcurrentDownloads") as? Int ?? 3
    }
}
