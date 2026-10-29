import Foundation
import Testing

@testable import Ondu

struct DurationFormatTests {

    @Test func dropsTheFractionInsteadOfRounding() {
        #expect(DurationFormat.string(125.6) == "2:05")
        #expect(DurationFormat.string(0.9) == "0:00")
    }

    @Test func aTrackReadsTheSameInTheListAsInThePlayer() {
        let artist = Artist(id: UUID(), name: "A", sortName: "A", slug: "a")
        let track = Track(
            id: UUID(), artistId: artist.id, albumArtistId: artist.id, albumId: UUID(),
            artist: artist, albumArtistSortName: "A", name: "T", disc: 1, number: 1,
            duration: 125.6, mimetype: "audio/mp4", streamUrl: "/stream/t")

        #expect(track.formattedDuration == DurationFormat.string(track.duration))
    }

    @Test func padsSecondsAndKeepsCountingMinutesPastAnHour() {
        #expect(DurationFormat.string(65) == "1:05")
        #expect(DurationFormat.string(3725) == "62:05")
    }

    /// Truncating the other way left "-0:00" on screen for the whole last second, which
    /// read as the song having ended while it was still playing.
    @Test func remainingTimeRoundsUp() {
        #expect(DurationFormat.remaining(0.4) == "-0:01")
        #expect(DurationFormat.remaining(1.0) == "-0:01")
        #expect(DurationFormat.remaining(1.2) == "-0:02")
        #expect(DurationFormat.remaining(125.6) == "-2:06")
    }

    @Test func nothingLeftReadsAsZero() {
        #expect(DurationFormat.remaining(0) == "-0:00")
        #expect(DurationFormat.remaining(-0.3) == "-0:00")
        #expect(DurationFormat.remaining(.nan) == "-0:00")
    }

    @Test func nonsenseReadsAsZero() {
        #expect(DurationFormat.string(.nan) == "0:00")
        #expect(DurationFormat.string(.infinity) == "0:00")
        #expect(DurationFormat.string(-3) == "0:00")
    }
}
