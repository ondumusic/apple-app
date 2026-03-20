import Foundation
import Testing
@testable import MusicBox

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
