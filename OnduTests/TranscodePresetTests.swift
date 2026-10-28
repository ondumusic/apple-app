import Foundation
import Testing

@testable import Ondu

struct TranscodePresetTests {

    private let server = TranscodePresetList(
        defaultId: "balanced",
        presets: [
            TranscodePreset(
                id: "balanced", name: "Balanced (160kbps)", codec: "opus", container: "ogg",
                mimetype: "audio/ogg", fileExtension: "opus", bitrate: 160),
            TranscodePreset(
                id: "small", name: "Small (64kbps)", codec: "opus", container: "ogg",
                mimetype: "audio/ogg", fileExtension: "opus", bitrate: 64),
        ])

    @Test func originalPlaysAsItIsWhenAVPlayerCanPlayIt() {
        #expect(server.resolve(.original, mimetype: "audio/flac") == nil)
        #expect(server.resolve(.original, mimetype: "audio/mpeg") == nil)
    }

    /// Ogg Vorbis never plays in AVPlayer, so Original still has to be transcoded, and
    /// the server's default is the preset for that.
    @Test func unsupportedFormatsAreTranscodedEvenAtOriginal() {
        #expect(server.resolve(.original, mimetype: "audio/ogg")?.id == "balanced")
    }

    @Test func aChosenPresetIsUsedByItsId() {
        #expect(server.resolve(.preset("small"), mimetype: "audio/flac")?.id == "small")
    }

    /// The server answers an id it doesn't know with 400 rather than its default, so
    /// a preset renamed out from under a stored choice has to fall back on this side.
    @Test func aPresetTheServerNoLongerHasFallsBackToItsDefault() {
        #expect(server.resolve(.preset("mobile_ogg"), mimetype: "audio/flac")?.id == "balanced")
    }

    @Test func theBuiltInListMatchesWhatOlderServersAccept() {
        #expect(TranscodePresetList.builtIn.defaultPreset?.id == "default_ogg")
        #expect(TranscodePresetList.builtIn.presets.map(\.id) == ["default_ogg", "mobile_ogg"])
    }

    @Test func decodesTheServersShape() throws {
        let json = """
            {"id":"default_ogg","name":"Default (192kbps)","codec":"opus","container":"ogg",
             "mimetype":"audio/ogg","extension":"opus","bitrate":192}
            """
        let preset = try JSONDecoder().decode(TranscodePreset.self, from: Data(json.utf8))
        #expect(preset.id == "default_ogg")
        #expect(preset.fileExtension == "opus")
        #expect(preset.bitrate == 192)
    }

    @Test func survivesARoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(server)
        #expect(try JSONDecoder().decode(TranscodePresetList.self, from: data) == server)
    }
}

struct TranscodeQualityTests {

    @Test func originalIsItsOwnWord() {
        #expect(TranscodeQuality.original.rawValue == "original")
        #expect(TranscodeQuality(rawValue: "original") == .original)
    }

    @Test func anythingElseIsAPresetId() {
        #expect(TranscodeQuality.preset("mobile_ogg").rawValue == "mobile_ogg")
        #expect(TranscodeQuality(rawValue: "mobile_ogg") == .preset("mobile_ogg"))
    }
}
