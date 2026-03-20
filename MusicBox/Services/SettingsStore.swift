import SwiftUI

nonisolated enum DownloadQuality: String, CaseIterable, Sendable {
    case original
    case defaultAAC = "default_aac"
    case mobileAAC = "mobile_aac"

    var displayName: String {
        switch self {
        case .original: "Original"
        case .defaultAAC: "Default (256kbps)"
        case .mobileAAC: "Mobile (128kbps)"
        }
    }
}

nonisolated enum StreamingQuality: String, CaseIterable, Sendable {
    case original
    case defaultADTS = "default_adts"
    case mobileADTS = "mobile_adts"

    var displayName: String {
        switch self {
        case .original: "Original"
        case .defaultADTS: "Default (256kbps)"
        case .mobileADTS: "Mobile (128kbps)"
        }
    }
}

nonisolated enum AccentColor: String, CaseIterable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, custom

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .custom: .blue // Placeholder — resolved via SettingsStore.resolvedAccentColor
        }
    }
}

@Observable
final class SettingsStore {
    // MARK: - Feature flags

    /// Set to true to show the download quality (transcode) option.
    static let enableDownloadQuality = true

    // MARK: - Settings

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

    var downloadQuality: DownloadQuality {
        didSet { UserDefaults.standard.set(downloadQuality.rawValue, forKey: "downloadQuality") }
    }

    var streamingQuality: StreamingQuality {
        didSet { UserDefaults.standard.set(streamingQuality.rawValue, forKey: "streamingQuality") }
    }

    var artworkTintedPlayer: Bool {
        didSet { UserDefaults.standard.set(artworkTintedPlayer, forKey: "artworkTintedPlayer") }
    }

    var accentColor: AccentColor {
        didSet { UserDefaults.standard.set(accentColor.rawValue, forKey: "accentColor") }
    }

    var customAccentRed: Double {
        didSet { UserDefaults.standard.set(customAccentRed, forKey: "customAccentRed") }
    }
    var customAccentGreen: Double {
        didSet { UserDefaults.standard.set(customAccentGreen, forKey: "customAccentGreen") }
    }
    var customAccentBlue: Double {
        didSet { UserDefaults.standard.set(customAccentBlue, forKey: "customAccentBlue") }
    }

    var customAccentColor: Color {
        Color(red: customAccentRed, green: customAccentGreen, blue: customAccentBlue)
    }

    /// The resolved accent color — use this everywhere instead of `accentColor.color`.
    var resolvedAccentColor: Color {
        accentColor == .custom ? customAccentColor : accentColor.color
    }

    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.crossfadeDuration = defaults.object(forKey: "crossfadeDuration") as? Double ?? 1.0
        self.maxConcurrentDownloads = defaults.object(forKey: "maxConcurrentDownloads") as? Int ?? 3
        self.isShuffled = defaults.bool(forKey: "isShuffled")
        self.repeatMode = RepeatMode(rawValue: defaults.string(forKey: "repeatMode") ?? "") ?? .off
        self.playbackCacheLimit = defaults.object(forKey: "playbackCacheLimit") as? Int64 ?? (2 * 1024 * 1024 * 1024) // 2 GB default
        self.downloadQuality = DownloadQuality(rawValue: defaults.string(forKey: "downloadQuality") ?? "") ?? .original
        self.streamingQuality = StreamingQuality(rawValue: defaults.string(forKey: "streamingQuality") ?? "") ?? .original
        self.artworkTintedPlayer = defaults.object(forKey: "artworkTintedPlayer") as? Bool ?? true
        self.accentColor = AccentColor(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .blue
        self.customAccentRed = defaults.object(forKey: "customAccentRed") as? Double ?? 1.0
        self.customAccentGreen = defaults.object(forKey: "customAccentGreen") as? Double ?? 0.4
        self.customAccentBlue = defaults.object(forKey: "customAccentBlue") as? Double ?? 0.0
        self.hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
    }
}
