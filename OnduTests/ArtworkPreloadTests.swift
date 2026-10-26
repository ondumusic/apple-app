import Foundation
import Testing

@testable import Ondu

struct ArtworkPreloadTests {
    private let large = ArtworkPreload.smallBatch + 1

    @Test func everythingPreloadsOnAnUnmeteredNetwork() {
        #expect(ArtworkPreload.decision(count: 5, isExpensive: false, isConstrained: false) == .now)
        #expect(ArtworkPreload.decision(count: large, isExpensive: false, isConstrained: false) == .now)
    }

    @Test func onMobileDataABigPreloadWaitsButASmallOneGoesAhead() {
        #expect(ArtworkPreload.decision(count: large, isExpensive: true, isConstrained: false) == .later)
        #expect(ArtworkPreload.decision(count: 5, isExpensive: true, isConstrained: false) == .now)
    }

    @Test func lowDataModePreloadsNothingNow() {
        #expect(ArtworkPreload.decision(count: large, isExpensive: false, isConstrained: true) == .later)
        #expect(ArtworkPreload.decision(count: 5, isExpensive: false, isConstrained: true) == .never)
    }
}
