import Testing
@testable import MusicBox

struct AudioFormatTests {

    // MARK: - Supported formats

    @Test func mp3Supported() {
        #expect(AudioFormat.isAVPlayerSupported("audio/mpeg"))
        #expect(AudioFormat.isAVPlayerSupported("audio/mp3"))
    }

    @Test func m4aSupported() {
        #expect(AudioFormat.isAVPlayerSupported("audio/mp4"))
        #expect(AudioFormat.isAVPlayerSupported("audio/m4a"))
        #expect(AudioFormat.isAVPlayerSupported("audio/x-m4a"))
    }

    @Test func aacSupported() {
        #expect(AudioFormat.isAVPlayerSupported("audio/aac"))
    }

    @Test func flacSupported() {
        #expect(AudioFormat.isAVPlayerSupported("audio/flac"))
        #expect(AudioFormat.isAVPlayerSupported("audio/x-flac"))
    }

    @Test func wavSupported() {
        #expect(AudioFormat.isAVPlayerSupported("audio/wav"))
        #expect(AudioFormat.isAVPlayerSupported("audio/x-wav"))
    }

    @Test func aiffSupported() {
        #expect(AudioFormat.isAVPlayerSupported("audio/aiff"))
        #expect(AudioFormat.isAVPlayerSupported("audio/x-aiff"))
    }

    // MARK: - Unsupported formats

    @Test func oggUnsupported() {
        #expect(!AudioFormat.isAVPlayerSupported("audio/ogg"))
        #expect(!AudioFormat.isAVPlayerSupported("audio/vorbis"))
    }

    @Test func opusUnsupported() {
        #expect(!AudioFormat.isAVPlayerSupported("audio/opus"))
    }

    @Test func webmUnsupported() {
        #expect(!AudioFormat.isAVPlayerSupported("audio/webm"))
    }

    @Test func unknownUnsupported() {
        #expect(!AudioFormat.isAVPlayerSupported("audio/unknown"))
        #expect(!AudioFormat.isAVPlayerSupported("video/mp4"))
        #expect(!AudioFormat.isAVPlayerSupported(""))
    }

    // MARK: - Case insensitivity

    @Test func caseInsensitive() {
        #expect(AudioFormat.isAVPlayerSupported("Audio/MPEG"))
        #expect(AudioFormat.isAVPlayerSupported("AUDIO/MP4"))
        #expect(AudioFormat.isAVPlayerSupported("Audio/Flac"))
    }

    // MARK: - File Extension

    @Test func fileExtensionForCommonTypes() {
        #expect(AudioFormat.fileExtension(for: "audio/mpeg") == "mp3")
        #expect(AudioFormat.fileExtension(for: "audio/mp3") == "mp3")
        #expect(AudioFormat.fileExtension(for: "audio/flac") == "flac")
        #expect(AudioFormat.fileExtension(for: "audio/x-flac") == "flac")
        #expect(AudioFormat.fileExtension(for: "audio/mp4") == "m4a")
        #expect(AudioFormat.fileExtension(for: "audio/m4a") == "m4a")
        #expect(AudioFormat.fileExtension(for: "audio/x-m4a") == "m4a")
        #expect(AudioFormat.fileExtension(for: "audio/aac") == "aac")
        #expect(AudioFormat.fileExtension(for: "audio/ogg") == "ogg")
        #expect(AudioFormat.fileExtension(for: "audio/vorbis") == "ogg")
        #expect(AudioFormat.fileExtension(for: "audio/wav") == "wav")
        #expect(AudioFormat.fileExtension(for: "audio/x-wav") == "wav")
    }

    @Test func fileExtensionDefaultFallback() {
        #expect(AudioFormat.fileExtension(for: "audio/unknown") == "mp3")
        #expect(AudioFormat.fileExtension(for: "") == "mp3")
    }

    @Test func fileExtensionCustomFallback() {
        #expect(AudioFormat.fileExtension(for: "audio/unknown", fallback: "bin") == "bin")
        #expect(AudioFormat.fileExtension(for: "audio/unknown", fallback: "") == "")
    }

    @Test func fileExtensionCaseInsensitive() {
        #expect(AudioFormat.fileExtension(for: "Audio/MPEG") == "mp3")
        #expect(AudioFormat.fileExtension(for: "AUDIO/FLAC") == "flac")
    }
}
