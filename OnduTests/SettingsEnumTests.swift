import Testing
@testable import Ondu

struct DownloadQualityTests {

    @Test func rawValuesMatchServerPresets() {
        #expect(DownloadQuality.original.rawValue == "original")
        #expect(DownloadQuality.defaultAAC.rawValue == "default_aac")
        #expect(DownloadQuality.mobileAAC.rawValue == "mobile_aac")
    }

    @Test func displayNames() {
        #expect(DownloadQuality.original.displayName == "Original")
        #expect(DownloadQuality.defaultAAC.displayName == "Default (256kbps)")
        #expect(DownloadQuality.mobileAAC.displayName == "Mobile (128kbps)")
    }

    @Test func initFromRawValue() {
        #expect(DownloadQuality(rawValue: "default_aac") == .defaultAAC)
        #expect(DownloadQuality(rawValue: "mobile_aac") == .mobileAAC)
        #expect(DownloadQuality(rawValue: "original") == .original)
        #expect(DownloadQuality(rawValue: "invalid") == nil)
    }

    @Test func allCasesCount() {
        #expect(DownloadQuality.allCases.count == 3)
    }
}

struct StreamingQualityTests {

    @Test func rawValuesMatchServerPresets() {
        #expect(StreamingQuality.original.rawValue == "original")
        #expect(StreamingQuality.defaultADTS.rawValue == "default_adts")
        #expect(StreamingQuality.mobileADTS.rawValue == "mobile_adts")
    }

    @Test func displayNames() {
        #expect(StreamingQuality.original.displayName == "Original")
        #expect(StreamingQuality.defaultADTS.displayName == "Default (256kbps)")
        #expect(StreamingQuality.mobileADTS.displayName == "Mobile (128kbps)")
    }

    @Test func initFromRawValue() {
        #expect(StreamingQuality(rawValue: "default_adts") == .defaultADTS)
        #expect(StreamingQuality(rawValue: "mobile_adts") == .mobileADTS)
        #expect(StreamingQuality(rawValue: "original") == .original)
        #expect(StreamingQuality(rawValue: "invalid") == nil)
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
