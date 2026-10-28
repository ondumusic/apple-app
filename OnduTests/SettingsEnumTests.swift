import Testing

@testable import Ondu

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
