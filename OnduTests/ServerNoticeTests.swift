import Foundation
import Testing

@testable import Ondu

struct ServerNoticeTests {

    private func decode(_ json: String) throws -> ServerNotice {
        try JSONDecoder.api.decode(ServerNotice.self, from: Data(json.utf8))
    }

    private let known = """
        {"id":"6f1a3f1e-0000-4000-8000-000000000001","code":"library_unavailable",
         "level":"warning","message":"No music was found in the music path.",
         "raisedAt":"2026-10-04T18:00:00Z"}
        """

    private let unknown = """
        {"id":"6f1a3f1e-0000-4000-8000-000000000002","code":"disk_filling_up",
         "level":"info","message":"The disk is nearly full.",
         "raisedAt":"2026-10-04T18:00:00Z"}
        """

    /// A code this build knows gets our own wording, which goes through the string
    /// catalogue and can say what to do about it.
    @Test func usesOurOwnTextForAKnownCode() throws {
        let notice = try decode(known)
        #expect(notice.known == .libraryUnavailable)
        #expect(!String(localized: notice.text).contains("No music was found"))
    }

    /// And the server's English for one it doesn't — which is what lets the server add
    /// notices without waiting for an app release.
    @Test func fallsBackToTheServersMessage() throws {
        let notice = try decode(unknown)
        #expect(notice.known == nil)
        #expect(String(localized: notice.text) == "The disk is nearly full.")
    }

    @Test func readsTheLevel() throws {
        #expect(try decode(known).level == .warning)
        #expect(try decode(unknown).level == .info)
    }

    /// A level invented later shouldn't fail to decode, and shouldn't shout either.
    @Test func treatsAnUnknownLevelAsInfo() throws {
        let json = unknown.replacingOccurrences(of: "\"info\"", with: "\"catastrophe\"")
        #expect(try decode(json).level == .info)
    }

    /// Sync sends everything currently raised rather than what changed, so an empty list
    /// has to mean "none" rather than "no news".
    @Test func anEmptyListDecodes() throws {
        let response = try JSONDecoder.api.decode(
            SyncResponse.self,
            from: Data(#"{"artists":[],"albums":[],"tracks":[],"deletions":[],"cursor":"c","complete":true}"#.utf8))
        #expect(response.notices.isEmpty)
    }

    @Test func noticesDecodeFromASyncResponse() throws {
        let json = """
            {"artists":[],"albums":[],"tracks":[],"deletions":[],"cursor":"c","complete":true,
             "notices":[\(known)]}
            """
        let response = try JSONDecoder.api.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.notices.count == 1)
        #expect(response.notices.first?.known == .libraryUnavailable)
    }
}
