import Foundation

/// A transcoding preset the server offers. Servers list theirs in `/info`: the ids have
/// changed before and that forced an app update, so the app no longer hardcodes them.
nonisolated struct TranscodePreset: Codable, Sendable, Hashable, Identifiable {
    let id: String
    /// Already in the user's language: the server translates it from the
    /// `Accept-Language` header URLSession sends on every request.
    let name: String
    let codec: String
    let container: String
    let mimetype: String
    let fileExtension: String
    let bitrate: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, codec, container, mimetype, bitrate
        case fileExtension = "extension"
    }
}

/// The presets a server offers, as it last reported them.
nonisolated struct TranscodePresetList: Codable, Sendable, Equatable {
    let defaultId: String
    let presets: [TranscodePreset]

    /// What every server offered before they started saying: the Ogg Opus presets, which
    /// play gapless, can be scrubbed while the server is still transcoding, and have their
    /// size up front so a download starts at once with real progress. Also what a server
    /// too old to list its presets is taken to have.
    static let builtIn = TranscodePresetList(
        defaultId: "default_ogg",
        presets: [
            TranscodePreset(
                id: "default_ogg", name: "Default (192kbps)", codec: "opus", container: "ogg",
                mimetype: "audio/ogg", fileExtension: "opus", bitrate: 192),
            TranscodePreset(
                id: "mobile_ogg", name: "Mobile (96kbps)", codec: "opus", container: "ogg",
                mimetype: "audio/ogg", fileExtension: "opus", bitrate: 96),
        ])

    var defaultPreset: TranscodePreset? {
        presets.first { $0.id == defaultId } ?? presets.first
    }

    /// Nil means the file plays or downloads as it is. A preset the server no longer has
    /// falls back to its default here because the server won't: it answers an unknown id
    /// with 400 rather than substituting.
    func resolve(_ quality: TranscodeQuality, mimetype: String) -> TranscodePreset? {
        switch quality {
        case .original:
            AudioFormat.isAVPlayerSupported(mimetype) ? nil : defaultPreset
        case .preset(let id):
            presets.first { $0.id == id } ?? defaultPreset
        }
    }
}

/// What to ask the server for: the file as it is, or one of its presets by id.
nonisolated enum TranscodeQuality: Hashable, Sendable, RawRepresentable {
    case original
    case preset(String)

    var rawValue: String {
        switch self {
        case .original: "original"
        case .preset(let id): id
        }
    }

    init(rawValue: String) {
        self = rawValue == "original" ? .original : .preset(rawValue)
    }
}
