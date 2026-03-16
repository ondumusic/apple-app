import Foundation

/// Audio format utilities for AVPlayer compatibility.
nonisolated enum AudioFormat {
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
