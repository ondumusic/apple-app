import Foundation
import Testing

@testable import Ondu

/// A column added in an update shouldn't appear in a table someone had already arranged.
struct ColumnVisibilityTests {

    private let defaults: Set<String> = ["disc", "year", "plays", "lastPlayed"]

    @Test func hidesAColumnThePreferenceNeverKnewAbout() {
        // Stored before Plays and Last Played existed, so it names neither.
        let hidden = ColumnVisibility.hidden(stored: ["year"], known: nil, defaults: defaults)
        #expect(hidden.contains("plays"))
        #expect(hidden.contains("lastPlayed"))
    }

    @Test func keepsAColumnTheUserTurnedOn() {
        let hidden = ColumnVisibility.hidden(
            stored: ["year"], known: ["year", "plays", "lastPlayed"], defaults: defaults)
        #expect(!hidden.contains("plays"))
    }

    @Test func keepsAColumnTheUserTurnedOff() {
        let hidden = ColumnVisibility.hidden(
            stored: ["plays"], known: ["plays", "lastPlayed"], defaults: defaults)
        #expect(hidden.contains("plays"))
        #expect(!hidden.contains("lastPlayed"))
    }

    @Test func usesTheDefaultsWhenNothingIsStored() {
        #expect(ColumnVisibility.hidden(stored: nil, known: nil, defaults: defaults) == defaults)
    }
}
