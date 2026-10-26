import Foundation

/// Which server preset a quality level asks for: the Ogg Opus presets, which play
/// gapless, can be scrubbed while the server is still transcoding, and have their size
/// up front so a download starts at once with real progress.
nonisolated enum TranscodePreset {

    /// Nil means the original file plays as it is.
    static func forStreaming(quality: StreamingQuality, mimetype: String) -> String? {
        if quality == .original, AudioFormat.isAVPlayerSupported(mimetype) { return nil }
        return quality == .mobile ? "mobile_ogg" : "default_ogg"
    }

    /// Nil means the original file is downloaded as it is.
    static func forDownload(quality: DownloadQuality, mimetype: String) -> String? {
        if quality == .original, AudioFormat.isAVPlayerSupported(mimetype) { return nil }
        return quality == .mobile ? "mobile_ogg" : "default_ogg"
    }
}
