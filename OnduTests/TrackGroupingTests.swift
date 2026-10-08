import Foundation
import Testing
@testable import Ondu

struct TrackGroupingTests {

    @Test func singleDiscAlbumGetsNoLabels() {
        let tracks = (1...5).map { makeTrack(disc: 1, number: $0) }
        #expect(TrackGrouping.discLabels(for: tracks).isEmpty)
    }

    @Test func labelsMarkTheFirstTrackOfEachDisc() {
        let tracks = (1...3).map { makeTrack(disc: 1, number: $0) }
            + (1...2).map { makeTrack(disc: 2, number: $0) }
        let labels = TrackGrouping.discLabels(for: tracks)
        #expect(labels.keys.sorted() == [0, 3])
        #expect(labels[0] == "Disc 1")
        #expect(labels[3] == "Disc 2")
    }

    /// A disc the order returns to later gets a second marker — the label describes the
    /// run of rows beneath it, not the disc as a whole.
    @Test func interleavedDiscsLabelEveryRun() {
        let tracks = [
            makeTrack(disc: 1, number: 1),
            makeTrack(disc: 2, number: 1),
            makeTrack(disc: 1, number: 2)
        ]
        #expect(TrackGrouping.discLabels(for: tracks).keys.sorted() == [0, 1, 2])
    }

    @Test func sectionLabelsAreKeyedByFlatIndex() {
        let single = [makeTrack(disc: 1, number: 1), makeTrack(disc: 1, number: 2)]
        let double = [makeTrack(disc: 1, number: 1), makeTrack(disc: 2, number: 1)]
        let labels = TrackGrouping.discLabels(forSections: [single, double])
        // The single-disc album contributes nothing; the next album's indices start at 2.
        #expect(labels.keys.sorted() == [2, 3])
        #expect(labels[2] == "Disc 1")
        #expect(labels[3] == "Disc 2")
    }

    @Test func emptyAlbumGetsNoLabels() {
        #expect(TrackGrouping.discLabels(for: []).isEmpty)
    }
}

// MARK: - Helpers

private let groupingArtist = Artist(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    name: "Test Artist",
    sortName: "Test Artist",
    slug: "test-artist"
)

private func makeTrack(disc: Int, number: Int) -> Track {
    Track(
        id: UUID(),
        artistId: groupingArtist.id,
        albumArtistId: groupingArtist.id,
        albumId: UUID(),
        artist: groupingArtist,
        albumArtistSortName: groupingArtist.sortName,
        name: "Track \(number)",
        disc: disc,
        number: number,
        duration: 100,
        mimetype: "audio/mp4",
        streamUrl: "/stream/test"
    )
}
