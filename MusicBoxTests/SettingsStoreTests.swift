import Foundation
import Testing
@testable import MusicBox

/// Serialized because all tests share UserDefaults.standard.
@Suite(.serialized)
struct SettingsStoreTests {

    private let testKeys = [
        "crossfadeDuration", "maxConcurrentDownloads", "isShuffled",
        "repeatMode", "playbackCacheLimit", "downloadQuality",
        "streamingQuality", "artworkTintedPlayer", "accentColor",
    ]

    private func clearDefaults() {
        for key in testKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Default values

    @Test func defaultCrossfadeDuration() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.crossfadeDuration == 1.0)
    }

    @Test func defaultMaxConcurrentDownloads() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.maxConcurrentDownloads == 3)
    }

    @Test func defaultIsShuffled() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.isShuffled == false)
    }

    @Test func defaultRepeatMode() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.repeatMode == .off)
    }

    @Test func defaultPlaybackCacheLimit() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.playbackCacheLimit == 2 * 1024 * 1024 * 1024) // 2 GB
    }

    @Test func defaultDownloadQuality() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.downloadQuality == .original)
    }

    @Test func defaultStreamingQuality() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.streamingQuality == .original)
    }

    @Test func defaultArtworkTintedPlayer() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.artworkTintedPlayer == true)
    }

    // MARK: - Persistence round-trip

    @Test func crossfadePersists() {
        clearDefaults()
        let store = SettingsStore()
        store.crossfadeDuration = 2.5
        let store2 = SettingsStore()
        #expect(store2.crossfadeDuration == 2.5)
        clearDefaults()
    }

    @Test func maxConcurrentDownloadsPersists() {
        clearDefaults()
        let store = SettingsStore()
        store.maxConcurrentDownloads = 5
        let store2 = SettingsStore()
        #expect(store2.maxConcurrentDownloads == 5)
        clearDefaults()
    }

    @Test func shufflePersists() {
        clearDefaults()
        let store = SettingsStore()
        store.isShuffled = true
        let store2 = SettingsStore()
        #expect(store2.isShuffled == true)
        clearDefaults()
    }

    @Test func repeatModePersists() {
        clearDefaults()
        let store = SettingsStore()
        store.repeatMode = .all
        let store2 = SettingsStore()
        #expect(store2.repeatMode == .all)
        clearDefaults()
    }

    @Test func downloadQualityPersists() {
        clearDefaults()
        let store = SettingsStore()
        store.downloadQuality = .mobileAAC
        let store2 = SettingsStore()
        #expect(store2.downloadQuality == .mobileAAC)
        clearDefaults()
    }

    @Test func streamingQualityPersists() {
        clearDefaults()
        let store = SettingsStore()
        store.streamingQuality = .mobileADTS
        let store2 = SettingsStore()
        #expect(store2.streamingQuality == .mobileADTS)
        clearDefaults()
    }

    @Test func artworkTintedPlayerPersists() {
        clearDefaults()
        let store = SettingsStore()
        store.artworkTintedPlayer = false
        let store2 = SettingsStore()
        #expect(store2.artworkTintedPlayer == false)
        clearDefaults()
    }

    @Test func accentColorPersists() {
        clearDefaults()
        let store = SettingsStore()
        store.accentColor = .purple
        let store2 = SettingsStore()
        #expect(store2.accentColor == .purple)
        clearDefaults()
    }

    // MARK: - Defaults (accent color)

    @Test func defaultAccentColor() {
        clearDefaults()
        let store = SettingsStore()
        #expect(store.accentColor == .blue)
    }

    // MARK: - Feature flags

    @Test func downloadQualityFeatureFlag() {
        #expect(SettingsStore.enableDownloadQuality == true)
    }
}
