import Foundation
import Testing
@testable import MusicBox

// MARK: - Helpers

/// SplitMix64 — a seeded generator makes the shuffle a pure function of its input,
/// so the spacing assertions below are exact, not statistical.
private nonisolated struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D4_9BBB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func makeItem(artist: UUID, album: UUID) -> QueueItem {
    let artistStruct = Artist(id: artist, name: "Artist", sortName: "Artist", slug: "artist")
    let track = Track(id: UUID(), artistId: artist, albumArtistId: artist, albumId: album,
                      artist: artistStruct, albumArtistSortName: "Artist",
                      name: "Track", disc: 1, number: 1, duration: 200,
                      mimetype: "audio/mp4", streamUrl: "/stream/test")
    return QueueItem(track: track)
}

private func longestRun<T: Equatable>(of values: [T]) -> Int {
    var run = 1, maxRun = values.isEmpty ? 0 : 1
    for (prev, cur) in zip(values, values.dropFirst()) {
        run = prev == cur ? run + 1 : 1
        maxRun = max(maxRun, run)
    }
    return maxRun
}

// MARK: - Tests

struct SmartShuffleTests {

    @Test func producesAPermutation() {
        let items = (0..<50).map { _ in makeItem(artist: UUID(), album: UUID()) }
        #expect(SmartShuffle.shuffledIndices(for: items).sorted() == Array(items.indices))
    }

    @Test func tinyQueuesSurvive() {
        #expect(SmartShuffle.shuffledIndices(for: []).isEmpty)
        let one = [makeItem(artist: UUID(), album: UUID())]
        #expect(SmartShuffle.shuffledIndices(for: one) == [0])
        let two = [makeItem(artist: UUID(), album: UUID()), makeItem(artist: UUID(), album: UUID())]
        #expect(SmartShuffle.shuffledIndices(for: two).sorted() == [0, 1])
    }

    @Test(arguments: 1...20) func spreadsAnArtistAcrossTheQueue(seed: Int) {
        // 4 tracks by one artist among 56 one-off artists: ideal spacing is 15.
        let artist = UUID(), album = UUID()
        let items = (0..<56).map { _ in makeItem(artist: UUID(), album: UUID()) }
            + (0..<4).map { _ in makeItem(artist: artist, album: album) }
        var rng = SeededGenerator(state: UInt64(seed))
        let order = SmartShuffle.shuffledIndices(for: items, using: &rng)
        let ranks = order.indices.filter { items[order[$0]].track.albumArtistId == artist }
        let gaps = zip(ranks.dropFirst(), ranks).map(-)
        #expect(gaps.allSatisfy { $0 >= 5 }, "artist clumped: ranks \(ranks)")
    }

    @Test(arguments: 1...20) func twoArtistQueueNeverRunsLong(seed: Int) {
        let a = UUID(), b = UUID()
        let items = (0..<10).map { _ in makeItem(artist: a, album: UUID()) }
            + (0..<10).map { _ in makeItem(artist: b, album: UUID()) }
        var rng = SeededGenerator(state: UInt64(seed))
        let order = SmartShuffle.shuffledIndices(for: items, using: &rng)
        let artists = order.map { items[$0].track.albumArtistId }
        #expect(longestRun(of: artists) <= 2)
    }

    @Test(arguments: 1...20) func spreadsAlbumsWithinAnArtist(seed: Int) {
        let artist = UUID(), first = UUID(), second = UUID()
        let items = (0..<8).map { _ in makeItem(artist: artist, album: first) }
            + (0..<8).map { _ in makeItem(artist: artist, album: second) }
        var rng = SeededGenerator(state: UInt64(seed))
        let order = SmartShuffle.shuffledIndices(for: items, using: &rng)
        let albums = order.map { items[$0].track.albumId }
        #expect(longestRun(of: albums) <= 2)
    }

    @Test func singleAlbumQueueIsAPlainShuffle() {
        let artist = UUID(), album = UUID()
        let items = (0..<30).map { _ in makeItem(artist: artist, album: album) }
        var rng = SeededGenerator(state: 7)
        let order = SmartShuffle.shuffledIndices(for: items, using: &rng)
        #expect(order.sorted() == Array(items.indices))
        #expect(order != Array(items.indices))
    }
}
