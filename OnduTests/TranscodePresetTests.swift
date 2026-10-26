import Foundation
import Testing

@testable import Ondu

struct TranscodePresetTests {

    @Test func originalPlaysAsItIsWhenAVPlayerCanPlayIt() {
        #expect(TranscodePreset.forStreaming(quality: .original, mimetype: "audio/flac") == nil)
        #expect(TranscodePreset.forDownload(quality: .original, mimetype: "audio/mpeg") == nil)
    }

    /// Ogg Vorbis never plays in AVPlayer, so Original still has to be transcoded.
    @Test func unsupportedFormatsAreTranscodedEvenAtOriginal() {
        #expect(TranscodePreset.forStreaming(quality: .original, mimetype: "audio/ogg") == "default_ogg")
        #expect(TranscodePreset.forDownload(quality: .original, mimetype: "audio/ogg") == "default_ogg")
    }

    @Test func levelsMapToTheOggPresets() {
        #expect(TranscodePreset.forStreaming(quality: .high, mimetype: "audio/flac") == "default_ogg")
        #expect(TranscodePreset.forStreaming(quality: .mobile, mimetype: "audio/flac") == "mobile_ogg")
        #expect(TranscodePreset.forDownload(quality: .high, mimetype: "audio/flac") == "default_ogg")
        #expect(TranscodePreset.forDownload(quality: .mobile, mimetype: "audio/flac") == "mobile_ogg")
    }
}
