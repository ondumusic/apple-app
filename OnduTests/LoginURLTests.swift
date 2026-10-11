import Foundation
import Testing

@testable import Ondu

struct LoginURLResolutionTests {

    @Test func hostnameOnly() {
        let url = LoginView.resolveServerURL("music.example.com")
        #expect(url?.absoluteString == "https://music.example.com/api")
    }

    @Test func hostnameWithPort() {
        let url = LoginView.resolveServerURL("music.example.com:4000")
        #expect(url?.absoluteString == "https://music.example.com:4000/api")
    }

    @Test func hostnameWithHttpScheme() {
        let url = LoginView.resolveServerURL("http://localhost:4000")
        #expect(url?.absoluteString == "http://localhost:4000/api")
    }

    @Test func hostnameWithHttpsScheme() {
        let url = LoginView.resolveServerURL("https://music.example.com")
        #expect(url?.absoluteString == "https://music.example.com/api")
    }

    @Test func customPathNotOverridden() {
        let url = LoginView.resolveServerURL("music.example.com/custom/path")
        #expect(url?.absoluteString == "https://music.example.com/custom/path")
    }

    @Test func customPathWithScheme() {
        let url = LoginView.resolveServerURL("https://myserver.com/v2/api")
        #expect(url?.absoluteString == "https://myserver.com/v2/api")
    }

    @Test func trailingSlashGetsApiAppended() {
        let url = LoginView.resolveServerURL("music.example.com/")
        #expect(url?.absoluteString == "https://music.example.com/api")
    }

    @Test func emptyStringReturnsNil() {
        #expect(LoginView.resolveServerURL("") == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        #expect(LoginView.resolveServerURL("   ") == nil)
    }

    @Test func whitespaceIsTrimmed() {
        let url = LoginView.resolveServerURL("  music.example.com  ")
        #expect(url?.absoluteString == "https://music.example.com/api")
    }

    @Test func ipAddress() {
        let url = LoginView.resolveServerURL("192.168.1.100:4000")
        #expect(url?.absoluteString == "https://192.168.1.100:4000/api")
    }

    @Test func localhostShorthand() {
        let url = LoginView.resolveServerURL("localhost:4000")
        #expect(url?.absoluteString == "https://localhost:4000/api")
    }
}

/// Release builds refuse a cleartext server; Debug keeps it so a local server can be
/// run without TLS. Both are asserted explicitly because tests build as Debug and would
/// otherwise only ever see the permissive half.
@Suite
struct LoginURLSchemePolicyTests {

    @Test func rejectsHttpWhenInsecureServersAreNotAllowed() {
        #expect(LoginView.resolveServerURL("http://192.168.1.10:4000", allowingInsecure: false) == nil)
        #expect(LoginView.resolveServerURL("http://localhost:4000", allowingInsecure: false) == nil)
    }

    @Test func allowsHttpWhenInsecureServersAreAllowed() {
        let url = LoginView.resolveServerURL("http://localhost:4000", allowingInsecure: true)
        #expect(url?.absoluteString == "http://localhost:4000/api")
    }

    /// A bare hostname still becomes https, so the common case never trips the rule.
    @Test func bareHostnameBecomesHttpsAndIsAccepted() {
        #expect(
            LoginView.resolveServerURL("music.example.com", allowingInsecure: false)?
                .absoluteString == "https://music.example.com/api")
    }

    @Test func httpsIsAcceptedEitherWay() {
        #expect(LoginView.resolveServerURL("https://music.example.com", allowingInsecure: false) != nil)
        #expect(LoginView.resolveServerURL("https://music.example.com", allowingInsecure: true) != nil)
    }

    /// Release is the configuration that ships, so it must be the strict one.
    @Test func releaseBuildsDisallowInsecureServers() {
        #if DEBUG
        #expect(LoginView.allowsInsecureServers)
        #else
        #expect(!LoginView.allowsInsecureServers)
        #endif
    }
}
