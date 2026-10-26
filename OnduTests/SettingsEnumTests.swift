import Testing

@testable import Ondu

struct DownloadQualityTests {

    /// Levels, not server presets: the preset is picked per device, see TranscodePreset.
    @Test func rawValuesAreLevels() {
        #expect(DownloadQuality.original.rawValue == "original")
        #expect(DownloadQuality.high.rawValue == "high")
        #expect(DownloadQuality.mobile.rawValue == "mobile")
    }

    @Test func displayNames() {
        #expect(DownloadQuality.original.displayName == "Original")
        #expect(DownloadQuality.high.displayName == "High")
        #expect(DownloadQuality.mobile.displayName == "Mobile")
    }

    @Test func initFromRawValue() {
        #expect(DownloadQuality(rawValue: "high") == .high)
        #expect(DownloadQuality(rawValue: "mobile") == .mobile)
        #expect(DownloadQuality(rawValue: "original") == .original)
        #expect(DownloadQuality(rawValue: "default_aac") == nil)
    }

    @Test func allCasesCount() {
        #expect(DownloadQuality.allCases.count == 3)
    }
}

struct StreamingQualityTests {

    @Test func rawValuesAreLevels() {
        #expect(StreamingQuality.original.rawValue == "original")
        #expect(StreamingQuality.high.rawValue == "high")
        #expect(StreamingQuality.mobile.rawValue == "mobile")
    }

    @Test func displayNames() {
        #expect(StreamingQuality.original.displayName == "Original")
        #expect(StreamingQuality.high.displayName == "High")
        #expect(StreamingQuality.mobile.displayName == "Mobile")
    }

    @Test func initFromRawValue() {
        #expect(StreamingQuality(rawValue: "high") == .high)
        #expect(StreamingQuality(rawValue: "mobile") == .mobile)
        #expect(StreamingQuality(rawValue: "original") == .original)
        #expect(StreamingQuality(rawValue: "default_adts") == nil)
    }

    @Test func allCasesCount() {
        #expect(StreamingQuality.allCases.count == 3)
    }
}

struct RepeatModeTests {

    @Test func rawValues() {
        #expect(RepeatMode.off.rawValue == "off")
        #expect(RepeatMode.one.rawValue == "one")
        #expect(RepeatMode.all.rawValue == "all")
    }

    @Test func initFromRawValue() {
        #expect(RepeatMode(rawValue: "off") == .off)
        #expect(RepeatMode(rawValue: "one") == .one)
        #expect(RepeatMode(rawValue: "all") == .all)
        #expect(RepeatMode(rawValue: "") == nil)
    }
}

struct AccentColorTests {

    @Test func allCasesCount() {
        #expect(AccentColor.allCases.count == 10)
    }

    @Test func rawValues() {
        #expect(AccentColor.blue.rawValue == "blue")
        #expect(AccentColor.purple.rawValue == "purple")
        #expect(AccentColor.custom.rawValue == "custom")
    }

    @Test func initFromRawValue() {
        #expect(AccentColor(rawValue: "blue") == .blue)
        #expect(AccentColor(rawValue: "purple") == .purple)
        #expect(AccentColor(rawValue: "invalid") == nil)
    }
}
