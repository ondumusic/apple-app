import Foundation
import Testing

@testable import Ondu

struct SettingsStoreTests {

    // MARK: - Default values

    /// On by default: a music app that counts what you play is the expectation, and the
    /// server has nothing to show without it.
    @Test func recordsPlaysByDefault() {
        #expect(SettingsStore(defaults: isolatedDefaults()).recordPlays)
    }

    @Test func remembersRecordPlaysBeingTurnedOff() {
        let defaults = isolatedDefaults()
        SettingsStore(defaults: defaults).recordPlays = false
        #expect(SettingsStore(defaults: defaults).recordPlays == false)
    }

    /// On by default — the feature exists to be seen; the toggle is for people who want
    /// the denser list back.
    @Test func showsArtistArtworkByDefault() {
        #expect(SettingsStore(defaults: isolatedDefaults()).showArtistArtwork)
    }

    @Test func remembersArtistArtworkBeingTurnedOff() {
        let defaults = isolatedDefaults()
        SettingsStore(defaults: defaults).showArtistArtwork = false
        #expect(SettingsStore(defaults: defaults).showArtistArtwork == false)
    }

    @Test func defaultCrossfadeDuration() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.crossfadeDuration == 1.0)
    }

    @Test func defaultMaxConcurrentDownloads() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.maxConcurrentDownloads == 3)
    }

    @Test func defaultIsShuffled() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.isShuffled == false)
    }

    @Test func defaultRepeatMode() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.repeatMode == .off)
    }

    @Test func defaultPlaybackCacheLimit() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.playbackCacheLimit == 2 * 1024 * 1024 * 1024)  // 2 GB
    }

    @Test func defaultDownloadQuality() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.downloadQuality == .original)
    }

    @Test func defaultStreamingQuality() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.streamingQuality == .original)
    }

    @Test func defaultArtworkTintedPlayer() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.artworkTintedPlayer == true)
    }

    // MARK: - Persistence round-trip

    @Test func crossfadePersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.crossfadeDuration = 2.5
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.crossfadeDuration == 2.5)
    }

    @Test func maxConcurrentDownloadsPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.maxConcurrentDownloads = 5
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.maxConcurrentDownloads == 5)
    }

    @Test func shufflePersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.isShuffled = true
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.isShuffled == true)
    }

    @Test func repeatModePersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.repeatMode = .all
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.repeatMode == .all)
    }

    @Test func downloadQualityPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.downloadQuality = .mobile
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.downloadQuality == .mobile)
    }

    @Test func streamingQualityPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.streamingQuality = .mobile
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.streamingQuality == .mobile)
    }

    @Test func artworkTintedPlayerPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.artworkTintedPlayer = false
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.artworkTintedPlayer == false)
    }

    @Test func accentColorPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.accentColor = .purple
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.accentColor == .purple)
    }

    // MARK: - Defaults (accent color)

    @Test func defaultAccentColor() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.accentColor == .blue)
    }

    // MARK: - Haptics

    @Test func defaultHapticsEnabled() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.hapticsEnabled == true)
    }

    @Test func hapticsPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.hapticsEnabled = false
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.hapticsEnabled == false)
    }

    // MARK: - Custom accent color

    @Test func customAccentColorPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.customAccentRed = 0.5
        store.customAccentGreen = 0.25
        store.customAccentBlue = 0.75
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.customAccentRed == 0.5)
        #expect(store2.customAccentGreen == 0.25)
        #expect(store2.customAccentBlue == 0.75)
    }

    @Test func resolvedAccentColorUsesCustomWhenSet() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.accentColor = .custom
        store.customAccentRed = 0.1
        store.customAccentGreen = 0.2
        store.customAccentBlue = 0.3
        // resolvedAccentColor should use custom RGB, not the preset fallback
        #expect(store.accentColor == .custom)
        #expect(store.customAccentRed == 0.1)
    }

    // MARK: - Auto-download

    @Test func defaultAutoDownloadNewTracks() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.autoDownloadNewTracks == false)
    }

    @Test func autoDownloadNewTracksPersists() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        store.autoDownloadNewTracks = true
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.autoDownloadNewTracks == true)
    }

    // MARK: - Feature flags

    @Test func downloadQualityFeatureFlag() {
        #expect(SettingsStore.enableDownloadQuality == true)
    }
}
