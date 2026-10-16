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

    @Test func nonsenseReadsAsZero() {
        #expect(DurationFormat.string(.nan) == "0:00")
        #expect(DurationFormat.string(.infinity) == "0:00")
        #expect(DurationFormat.string(-3) == "0:00")
    }
}
