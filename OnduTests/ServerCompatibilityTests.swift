import Foundation
import Testing

@testable import Ondu

struct ServerCompatibilityTests {

    private func compare(server: Int, supported: Int = 1) -> ServerCompatibility {
        ServerCompatibility.compare(
            serverAPIVersion: server, serverVersion: "1.3.0",
            supported: supported)
    }

    @Test func matchingVersionsAreFine() {
        #expect(compare(server: 1) == .ok)
    }

    /// The server bumps its API version only when it breaks clients, so a higher one
    /// means this build is the side that can't keep up.
    @Test func aHigherServerVersionMeansTheAppIsBehind() {
        #expect(compare(server: 2) == .appTooOld(serverVersion: "1.3.0"))
    }

    /// The app ships on Apple's schedule and the server on its owner's, so this happens
    /// as readily as the other way round.
    @Test func aLowerServerVersionMeansTheServerIsBehind() {
        #expect(compare(server: 1, supported: 2) == .serverTooOld(serverVersion: "1.3.0"))
    }

    @Test func showsNothingWhenTheVersionsMatch() {
        #expect(!ServerCompatibility.ok.shouldShow(dismissedVersion: ""))
    }

    @Test func showsAMismatchNobodyHasDismissed() {
        #expect(compare(server: 2).shouldShow(dismissedVersion: ""))
    }

    @Test func staysDismissedForTheVersionItWasAbout() {
        #expect(!compare(server: 2).shouldShow(dismissedVersion: "1.3.0"))
    }

    /// A server upgrade that doesn't fix the mismatch is worth mentioning again — the
    /// dismissal was about the version, not about the subject.
    @Test func speaksUpAgainAfterTheServerChangesVersion() {
        let laterServer = ServerCompatibility.compare(
            serverAPIVersion: 2, serverVersion: "1.4.0", supported: 1)
        #expect(laterServer.shouldShow(dismissedVersion: "1.3.0"))
    }

    @Test func namesTheServerVersionInTheMessage() {
        let message = String(localized: try! #require(compare(server: 2).message))
        #expect(message.contains("1.3.0"))
    }
}
