import Foundation
import Testing

@testable import Ondu

struct APIOriginTests {
    private let base = URL(string: "https://music.example.com/api")!

    private func sameOrigin(_ string: String) -> Bool {
        APIService.isSameOrigin(URL(string: string)!, as: base)
    }

    @Test func theServersOwnURLsGetTheToken() {
        #expect(sameOrigin("https://music.example.com/stream/1"))
        #expect(sameOrigin("https://MUSIC.example.com/stream/1"))
        #expect(sameOrigin("https://music.example.com:443/stream/1"))
    }

    @Test func anyOtherHostPortOrSchemeDoesNot() {
        #expect(!sameOrigin("https://elsewhere.example.com/stream/1"))
        #expect(!sameOrigin("https://music.example.com.evil.test/stream/1"))
        #expect(!sameOrigin("https://music.example.com:8443/stream/1"))
        #expect(!sameOrigin("http://music.example.com/stream/1"))
    }

    @Test func aURLWithNoHostDoesNot() {
        #expect(!sameOrigin("/stream/1"))
    }

    @Test func anExplicitPortOnTheServerMatchesOnlyThatPort() {
        let base = URL(string: "http://192.168.1.10:4000/api")!
        #expect(APIService.isSameOrigin(URL(string: "http://192.168.1.10:4000/stream/1")!, as: base))
        #expect(!APIService.isSameOrigin(URL(string: "http://192.168.1.10/stream/1")!, as: base))
    }
}
