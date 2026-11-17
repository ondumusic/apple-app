import Foundation
import Testing

@testable import Ondu

// The queue as a user experiences it: what has played, what is playing, and what is to
// come, through shuffle, edits and skips. History is what played and never rewrites
// itself; only what's still to come gets reordered.

private let artist = Artist(id: UUID(), name: "Artist", sortName: "Artist", slug: "artist")

private func makeTrack(_ name: String) -> Track {
    Track(
        id: UUID(), artistId: artist.id, albumArtistId: artist.id,
        albumId: UUID(), artist: artist, albumArtistSortName: artist.sortName,
        name: name, disc: 1, number: 1, duration: 200,
        mimetype: "audio/mp4", streamUrl: "/stream/test")
}

private func items(_ names: String...) -> [QueueItem] {
    names.map { QueueItem(track: makeTrack($0)) }
}

private func makePlayer() -> PlayerService {
    let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("queue-behaviour-tests/\(UUID().uuidString).json")
    return PlayerService(
        api: api, settings: makeTestSettings(), stateStore: PlaybackStateStore(fileURL: stateURL))
}

extension PlayerService {
    /// Most recent first, as the queue screen lists it.
    fileprivate var history: [String] { historyEntries.map(\.item.track.name) }
    fileprivate var current: String? { currentQueueItem?.track.name }
    fileprivate var upNext: [String] { upNextEntries.map(\.item.track.name) }
}

/// A queue in a shuffled play order of the test's choosing.
private func shuffled(_ names: [String], playOrder: [Int], currentIndex: Int) -> PlayerService {
    let player = makePlayer()
    player.playNow(queue: names.map { QueueItem(track: makeTrack($0)) })
    player.playOrder = playOrder
    player.isShuffled = true
    player.currentIndex = currentIndex
    return player
}

/// Album A–E shuffled to C, A, E, B, D: C and A played, E playing, B and D to come.
private func shuffledMidway() -> PlayerService {
    shuffled(["A", "B", "C", "D", "E"], playOrder: [2, 0, 4, 1, 3], currentIndex: 2)
}

struct QueueShuffleTests {

    @Test func shuffleOnKeepsHistoryAndCurrent() {
        let player = makePlayer()
        player.playNow(queue: items("A", "B", "C", "D", "E", "F"), startingAt: 2)

        player.toggleShuffle()

        #expect(player.history == ["B", "A"])
        #expect(player.current == "C")
        #expect(Set(player.upNext) == ["D", "E", "F"])
    }

    @Test func shuffleOffNeverBringsBackWhatPlayed() {
        let player = shuffledMidway()

        player.toggleShuffle()

        #expect(!player.isShuffled)
        #expect(player.history == ["A", "C"])
        #expect(player.current == "E")
        #expect(player.upNext == ["B", "D"])
    }

    /// Unplayed tracks from before the current one come back too, in album order.
    @Test func shuffleOffPutsWhatsLeftInQueueOrder() {
        let player = shuffled(
            ["1", "2", "3", "4", "5", "6", "7", "8"], playOrder: [6, 3, 7, 0, 1, 2, 4, 5], currentIndex: 1)

        player.toggleShuffle()

        #expect(player.history == ["7"])
        #expect(player.current == "4")
        #expect(player.upNext == ["1", "2", "3", "5", "6", "8"])
    }

    @Test func togglingShuffleBackAndForthLeavesHistoryAlone() {
        let player = makePlayer()
        player.playNow(queue: items("A", "B", "C", "D", "E", "F"), startingAt: 3)

        for _ in 0..<4 { player.toggleShuffle() }

        #expect(!player.isShuffled)
        #expect(player.history == ["C", "B", "A"])
        #expect(player.current == "D")
        #expect(player.upNext == ["E", "F"])
    }

    @Test func shuffledPlayDealsTheWholeQueue() {
        let player = makePlayer()
        player.playShuffled(queue: items("A", "B", "C", "D"))

        #expect(player.isShuffled)
        #expect(player.history.isEmpty)
        #expect(Set([player.current].compactMap { $0 } + player.upNext) == ["A", "B", "C", "D"])
    }

    @Test func playTurnsShuffleOff() {
        let player = makePlayer()
        player.playShuffled(queue: items("A", "B"))

        player.playNow(queue: items("C", "D", "E"), startingAt: 1)

        #expect(!player.isShuffled)
        #expect(player.history == ["C"])
        #expect(player.upNext == ["E"])
    }
}

struct QueueAddWhileShuffledTests {

    @Test func playNextKeepsTheSelectionsOrder() {
        let player = shuffledMidway()

        player.playNext(queue: items("X", "Y", "Z"))

        #expect(player.upNext == ["X", "Y", "Z", "B", "D"])
        #expect(player.history == ["A", "C"])
    }

    @Test func playNextStaysFirstWhenShuffleTurnsOff() {
        let player = shuffledMidway()
        player.playNext(queue: items("X", "Y"))

        player.toggleShuffle()

        #expect(player.upNext == ["X", "Y", "B", "D"])
    }

    @Test func addToEndKeepsTheSelectionsOrder() {
        let player = shuffledMidway()

        player.addToEnd(queue: items("X", "Y", "Z"))

        #expect(player.upNext == ["B", "D", "X", "Y", "Z"])
    }

    @Test func addToEndStaysLastWhenShuffleTurnsOff() {
        let player = shuffledMidway()
        player.addToEnd(queue: items("X", "Y"))

        player.toggleShuffle()

        #expect(player.upNext == ["B", "D", "X", "Y"])
    }
}

struct QueueEditTests {

    @Test func removingWhileShuffledLeavesHistoryAndCurrent() {
        let player = shuffledMidway()

        player.removeFromQueue(at: IndexSet(integer: 0))

        #expect(player.history == ["A", "C"])
        #expect(player.current == "E")
        #expect(player.upNext == ["D"])
    }

    @Test func movingUnshuffledChangesTheQueueOrderForGood() {
        let player = makePlayer()
        player.playNow(queue: items("A", "B", "C", "D", "E"), startingAt: 0)

        player.moveQueueItems(from: IndexSet(integer: 3), to: 0)
        #expect(player.upNext == ["E", "B", "C", "D"])

        player.toggleShuffle()
        player.toggleShuffle()
        #expect(player.upNext == ["E", "B", "C", "D"])
    }

    @Test func movingWhileShuffledOnlyChangesTheShuffledOrder() {
        let player = shuffledMidway()

        player.moveQueueItems(from: IndexSet(integer: 1), to: 0)
        #expect(player.upNext == ["D", "B"])

        player.toggleShuffle()
        #expect(player.upNext == ["B", "D"])
    }

    @Test func removingOneOfTheSameTrackQueuedTwiceKeepsTheOther() {
        let player = makePlayer()
        let repeated = makeTrack("R")
        let first = QueueItem(track: repeated)
        let second = QueueItem(track: repeated)
        player.playNow(queue: items("A") + [first, second], startingAt: 0)

        player.removeFromQueue(at: IndexSet(integer: 0))

        #expect(player.upNextEntries.map(\.item.id) == [second.id])
    }
}

struct QueueNavigationTests {

    @Test func skippingAheadMovesTheTracksInBetweenToHistory() {
        let player = makePlayer()
        player.playNow(queue: items("A", "B", "C", "D", "E"), startingAt: 0)

        player.skipTo(queueIndex: 3)

        #expect(player.history == ["C", "B", "A"])
        #expect(player.current == "D")
        #expect(player.upNext == ["E"])
    }

    @Test func skippingBackIntoHistoryRewindsToIt() {
        let player = makePlayer()
        player.playNow(queue: items("A", "B", "C", "D", "E"), startingAt: 3)

        player.skipTo(queueIndex: 1)

        #expect(player.history == ["A"])
        #expect(player.current == "B")
        #expect(player.upNext == ["C", "D", "E"])
    }

    @Test func backThenSkipReturnsToWhereItWas() {
        let player = makePlayer()
        player.playNow(queue: items("A", "B", "C"), startingAt: 1)

        player.back()
        #expect(player.current == "A")
        #expect(player.upNext == ["B", "C"])

        player.skip()
        #expect(player.current == "B")
        #expect(player.history == ["A"])
    }

    @Test func theEndOfTheQueueCuesUpTheStartInTheOrderItPlayed() {
        let player = shuffledMidway()
        player.skip()
        player.skip()

        player.skip()

        #expect(!player.isPlaying)
        #expect(player.history.isEmpty)
        #expect(player.current == "C")
        #expect(player.upNext == ["A", "E", "B", "D"])
    }

    @Test func repeatAllPlaysTheSameOrderAgain() {
        let player = shuffledMidway()
        player.repeatMode = .all
        player.skip()
        player.skip()

        player.skip()

        #expect(player.history.isEmpty)
        #expect(player.current == "C")
        #expect(player.upNext == ["A", "E", "B", "D"])
    }
}
