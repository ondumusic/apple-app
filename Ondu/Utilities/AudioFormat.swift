import Foundation

/// Audio format utilities for AVPlayer compatibility.
nonisolated enum AudioFormat {
    /// Returns a file extension for a given audio MIME type, or the fallback if unknown.
    static func fileExtension(for mimetype: String, fallback: String = "mp3") -> String {
        switch mimetype.lowercased() {
        case "audio/mpeg", "audio/mp3": "mp3"
        case "audio/flac", "audio/x-flac": "flac"
        case "audio/mp4", "audio/m4a", "audio/x-m4a": "m4a"
        case "audio/aac": "aac"
        case "audio/ogg", "audio/vorbis": "ogg"
        case "audio/wav", "audio/x-wav": "wav"
        default: fallback
        }
    }

    /// MIME types that AVPlayer can play natively.
    static func isAVPlayerSupported(_ mimetype: String) -> Bool {
        switch mimetype.lowercased() {
        case "audio/mpeg", "audio/mp3",
            "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac",
            "audio/flac", "audio/x-flac",
            "audio/wav", "audio/x-wav",
            "audio/aiff", "audio/x-aiff":
            true
        default:
            false
        }
    }
}
