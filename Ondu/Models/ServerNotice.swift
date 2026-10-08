import Foundation

/// Something the server wants to say — a library path that has gone missing, and
/// whatever else it learns to report later.
///
/// `code` is the contract and `message` is the safety net: we show our own wording for
/// codes we know, so it's localised and says what to do, and fall back to the server's
/// English for codes added after this build shipped. That fallback is the whole reason
/// the server can add notices without an app update.
nonisolated struct ServerNotice: Identifiable, Sendable, Equatable {
    let id: UUID
    let code: String
    let level: Level
    /// The server's own English. Shown only for codes this build doesn't know.
    let message: String
    let raisedAt: Date

    nonisolated enum Level: String, Sendable {
        case info
        case warning

        /// Anything the server invents later is worth showing, and worth showing quietly
        /// rather than as an alarm.
        init(rawValue: String) {
            self = rawValue == "warning" ? .warning : .info
        }
    }

    /// The codes this build has its own words for.
    nonisolated enum Known: String {
        case libraryUnavailable = "library_unavailable"
    }

    var known: Known? { Known(rawValue: code) }

    var text: LocalizedStringResource {
        switch known {
        case .libraryUnavailable:
            "Your server can't reach its music folder, so the library may be incomplete."
        case .none:
            "\(message)"
        }
    }
}

extension ServerNotice: Decodable {
    nonisolated enum CodingKeys: String, CodingKey {
        case id, code, level, message, raisedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        level = Level(rawValue: try container.decodeIfPresent(String.self, forKey: .level) ?? "info")
        message = try container.decode(String.self, forKey: .message)
        raisedAt = try container.decode(Date.self, forKey: .raisedAt)
    }
}
