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

    /// The app icon's own blue. The system blue is lighter and greener than anything in
    /// the icon, so the default accent didn't look like it belonged to the app it was
    /// accenting.
    ///
    /// Both ends come out of the icon's background gradient, which runs #4C84FF at the
    /// top to #214AE3 at the bottom: light mode takes the middle of it, dark mode the
    /// top, because the middle goes muddy against a dark ground. The other presets are
    /// system colours and adapt on their own; this one has to say how.
    static let iconBlue = Color(
        light: .srgb(0.219, 0.406, 0.946),
        dark: .srgb(0.300, 0.519, 1.000)
    )

    var color: Color {
        switch self {
        case .blue: Self.iconBlue
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

    /// Output volume, 0...1. Applied to the AVPlayers rather than the system volume.
    var volume: Double {
        didSet { defaults.set(volume, forKey: "volume") }
    }

    var crossfadeDuration: Double {
        didSet { defaults.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }

    var maxConcurrentDownloads: Int {
        didSet { defaults.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads") }
    }

    var isShuffled: Bool {
        didSet { defaults.set(isShuffled, forKey: "isShuffled") }
    }

    /// Artwork in the macOS artists list. Really a density switch: with it off the rows
    /// lose the circle and shrink back, which fits about a quarter more artists on screen.
    var showArtistArtwork: Bool {
        didSet { defaults.set(showArtistArtwork, forKey: "showArtistArtwork") }
    }

    /// Report finished listens to the server, which counts them across every device.
    /// Off stops this device reporting; it doesn't hide what's already counted, and
    /// other clients keep counting.
    var recordPlays: Bool {
        didSet { defaults.set(recordPlays, forKey: "recordPlays") }
    }

    /// Scale playback so every track lands near the same loudness. See
    /// `LoudnessNormalization` for why this can only ever make things quieter.
    var normalizeVolume: Bool {
        didSet {
            defaults.set(normalizeVolume, forKey: "normalizeVolume")
            onNormalizeVolumeChange?()
        }
    }

    /// Installed by `PlayerService` so the toggle lands on the track already playing
    /// instead of the next one. Settings has no player in its environment to call.
    @ObservationIgnored var onNormalizeVolumeChange: (() -> Void)?

    var repeatMode: RepeatMode {
        didSet { defaults.set(repeatMode.rawValue, forKey: "repeatMode") }
    }

    /// Maximum playback cache size in bytes. 0 means unlimited.
    var playbackCacheLimit: Int64 {
        didSet { defaults.set(playbackCacheLimit, forKey: "playbackCacheLimit") }
    }

    var downloadQuality: DownloadQuality {
        didSet { defaults.set(downloadQuality.rawValue, forKey: "downloadQuality") }
    }

    var streamingQuality: StreamingQuality {
        didSet { defaults.set(streamingQuality.rawValue, forKey: "streamingQuality") }
    }

    var artworkTintedPlayer: Bool {
        didSet { defaults.set(artworkTintedPlayer, forKey: "artworkTintedPlayer") }
    }

    /// Whether the mini player floats above *other apps'* windows while Ondu is in
    /// the background. Off by default, which is what the window already did — a window
    /// that outranks everything on screen is a thing to opt into, not to discover.
    var miniPlayerAlwaysOnTop: Bool {
        didSet { defaults.set(miniPlayerAlwaysOnTop, forKey: "miniPlayerAlwaysOnTop") }
    }

    var accentColor: AccentColor {
        didSet { defaults.set(accentColor.rawValue, forKey: "accentColor") }
    }

    var customAccentRed: Double {
        didSet { defaults.set(customAccentRed, forKey: "customAccentRed") }
    }
    var customAccentGreen: Double {
        didSet { defaults.set(customAccentGreen, forKey: "customAccentGreen") }
    }
    var customAccentBlue: Double {
        didSet { defaults.set(customAccentBlue, forKey: "customAccentBlue") }
    }

    var customAccentColor: Color {
        Color(red: customAccentRed, green: customAccentGreen, blue: customAccentBlue)
    }

    /// The resolved accent color — use this everywhere instead of `accentColor.color`.
    var resolvedAccentColor: Color {
        accentColor == .custom ? customAccentColor : accentColor.color
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    var autoDownloadNewTracks: Bool {
        didSet { defaults.set(autoDownloadNewTracks, forKey: "autoDownloadNewTracks") }
    }

    /// Where these persist. Injectable so tests get their own suite: every test that
    /// builds a PlayerService builds one of these, and sharing
    /// `UserDefaults.standard` across tests running in parallel meant they wrote each
    /// other's volume, shuffle flag and repeat mode out from under themselves.
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.volume = defaults.object(forKey: "volume") as? Double ?? 1.0
        self.crossfadeDuration = defaults.object(forKey: "crossfadeDuration") as? Double ?? 1.0
        self.maxConcurrentDownloads = defaults.object(forKey: "maxConcurrentDownloads") as? Int ?? 3
        self.isShuffled = defaults.bool(forKey: "isShuffled")
        self.normalizeVolume = defaults.object(forKey: "normalizeVolume") as? Bool ?? true
        self.recordPlays = defaults.object(forKey: "recordPlays") as? Bool ?? true
        self.showArtistArtwork = defaults.object(forKey: "showArtistArtwork") as? Bool ?? true
        self.repeatMode = RepeatMode(rawValue: defaults.string(forKey: "repeatMode") ?? "") ?? .off
        self.playbackCacheLimit = defaults.object(forKey: "playbackCacheLimit") as? Int64 ?? (2 * 1024 * 1024 * 1024) // 2 GB default
        self.downloadQuality = DownloadQuality(rawValue: defaults.string(forKey: "downloadQuality") ?? "") ?? .original
        self.streamingQuality = StreamingQuality(rawValue: defaults.string(forKey: "streamingQuality") ?? "") ?? .original
        self.artworkTintedPlayer = defaults.object(forKey: "artworkTintedPlayer") as? Bool ?? true
        self.miniPlayerAlwaysOnTop = defaults.object(forKey: "miniPlayerAlwaysOnTop") as? Bool ?? false
        self.accentColor = AccentColor(rawValue: defaults.string(forKey: "accentColor") ?? "") ?? .blue
        self.customAccentRed = defaults.object(forKey: "customAccentRed") as? Double ?? 1.0
        self.customAccentGreen = defaults.object(forKey: "customAccentGreen") as? Double ?? 0.4
        self.customAccentBlue = defaults.object(forKey: "customAccentBlue") as? Double ?? 0.0
        self.hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        self.autoDownloadNewTracks = defaults.bool(forKey: "autoDownloadNewTracks")
    }
}
