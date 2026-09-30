import Foundation

/// Whether this build and the server it's talking to speak the same API.
///
/// `apiVersion` is an integer the server bumps only when it breaks existing clients, so a
/// mismatch is a fact rather than a judgement — and it can point either way, because the
/// app and the server update on their own schedules.
nonisolated enum ServerCompatibility: Sendable, Equatable {
    case ok
    /// The server has moved on; this build can't keep up.
    case appTooOld(serverVersion: String)
    /// This build expects an API the server doesn't have yet.
    case serverTooOld(serverVersion: String)

    /// Named the side that's behind first, so the first three words say who has to act.
    /// The server's own version is what's shown rather than the API integer: "1.3.0" is
    /// what you look for when you go to update it.
    var message: LocalizedStringResource? {
        switch self {
        case .ok:
            nil
        case .appTooOld(let serverVersion):
            "MusicBox is out of date — your server (\(serverVersion)) needs a newer version of the app."
        case .serverTooOld(let serverVersion):
            "Your server is out of date — MusicBox needs a newer server than \(serverVersion)."
        }
    }

    /// What a dismissal is remembered against: say it once per server version, not once
    /// ever, so an upgrade that doesn't fix it speaks up again.
    var serverVersion: String? {
        switch self {
        case .ok: nil
        case .appTooOld(let version), .serverTooOld(let version): version
        }
    }

    /// Said once per server version rather than once ever: a dismissal that outlived the
    /// condition would hide a real problem, and one that came back every launch would be
    /// nagging about something the user can't fix on the spot.
    func shouldShow(dismissedVersion: String) -> Bool {
        guard let serverVersion else { return false }
        return serverVersion != dismissedVersion
    }

    static func compare(serverAPIVersion: Int, serverVersion: String,
                        supported: Int) -> ServerCompatibility {
        if serverAPIVersion > supported { return .appTooOld(serverVersion: serverVersion) }
        if serverAPIVersion < supported { return .serverTooOld(serverVersion: serverVersion) }
        return .ok
    }
}
