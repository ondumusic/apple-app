import Foundation
import Testing
@testable import MusicBox

// MARK: - Helpers

private let testArtist = Artist(id: UUID(), name: "Artist", sortName: "Artist", slug: "artist")

private func makeTrack(name: String = "Track", albumId: UUID = UUID(),
                       disc: Int = 1, number: Int = 1) -> Track {
    Track(id: UUID(), artistId: testArtist.id, albumArtistId: testArtist.id,
          albumId: albumId, artist: testArtist, albumArtistSortName: testArtist.sortName,
          name: name, disc: disc, number: number, duration: 200,
          mimetype: "audio/mp4", streamUrl: "/stream/test")
}

private func makeQueueItem(name: String = "Track", albumId: UUID = UUID(),
                           disc: Int = 1, number: Int = 1) -> QueueItem {
    QueueItem(track: makeTrack(name: name, albumId: albumId, disc: disc, number: number))
}

private func makePlayer() -> PlayerService {
    let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
    let settings = SettingsStore()
    return PlayerService(api: api, settings: settings)
}

// MARK: - Play Now

struct PlayerPlayNowTests {

    @Test func playNowSetsQueue() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 1)

        #expect(player.queue.count == 3)
        #expect(player.currentIndex == 1)
        #expect(player.shuffledIndices == nil)
    }

    @Test func playNowClearsShuffle() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        // First shuffle
        player.playShuffled(queue: items)
        #expect(player.shuffledIndices != nil)

        // Then play now — should clear shuffle
        player.playNow(queue: [makeQueueItem(name: "C")], startingAt: 0)
        #expect(player.shuffledIndices == nil)
    }
}

// MARK: - Play Shuffled

struct PlayerShuffleTests {

    @Test func playShuffledSetsIndices() {
        let player = makePlayer()
        let items = (0..<10).map { makeQueueItem(name: "T\($0)") }
        player.playShuffled(queue: items)

        #expect(player.queue.count == 10)
        #expect(player.shuffledIndices != nil)
        #expect(player.shuffledIndices?.count == 10)
        #expect(player.currentIndex == 0)
    }

    @Test func playShuffledIsPermutation() {
        let player = makePlayer()
        let items = (0..<10).map { makeQueueItem(name: "T\($0)") }
        player.playShuffled(queue: items)

        let indices = player.shuffledIndices!
        #expect(Set(indices) == Set(0..<10))
    }

    @Test func toggleShuffleOn() {
        let player = makePlayer()
        let items = (0..<5).map { makeQueueItem(name: "T\($0)") }
        player.playNow(queue: items, startingAt: 2)

        player.toggleShuffle()

        #expect(player.isShuffled)
        #expect(player.shuffledIndices != nil)
        // Current track should be at position 0 in shuffled order
        #expect(player.currentIndex == 0)
        #expect(player.shuffledIndices?[0] == 2)
    }

    @Test func toggleShuffleOff() {
        let player = makePlayer()
        let items = (0..<5).map { makeQueueItem(name: "T\($0)") }
        player.playNow(queue: items, startingAt: 0)
        player.toggleShuffle()
        let realIndex = player.effectiveIndex

        player.toggleShuffle()

        #expect(!player.isShuffled)
        #expect(player.shuffledIndices == nil)
        #expect(player.currentIndex == realIndex)
    }

    @Test func playShuffledEmptyQueueNoOp() {
        let player = makePlayer()
        player.playShuffled(queue: [])

        #expect(player.queue.isEmpty)
        #expect(player.shuffledIndices == nil)
    }
}

// MARK: - Play Next / Add to End

struct PlayerQueueInsertTests {

    @Test func playNextInsertsAfterCurrent() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 0)

        player.playNext(queue: [makeQueueItem(name: "X")])

        #expect(player.queue.count == 4)
        #expect(player.queue[1].track.name == "X")
        #expect(player.queueConfirmation == .playNext(1))
    }

    @Test func playNextOnEmptyQueueStartsPlayback() {
        let player = makePlayer()
        player.playNext(queue: [makeQueueItem(name: "A")])

        #expect(player.queue.count == 1)
        #expect(player.queue[0].track.name == "A")
    }

    @Test func addToEndAppendsToQueue() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)

        player.addToEnd(queue: [makeQueueItem(name: "X"), makeQueueItem(name: "Y")])

        #expect(player.queue.count == 4)
        #expect(player.queue[2].track.name == "X")
        #expect(player.queue[3].track.name == "Y")
        #expect(player.queueConfirmation == .addedToQueue(2))
    }

    @Test func addToEndOnEmptyQueueStartsPlayback() {
        let player = makePlayer()
        player.addToEnd(queue: [makeQueueItem(name: "A")])

        #expect(player.queue.count == 1)
    }

    @Test func playNextEmptyItemsNoOp() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")], startingAt: 0)
        player.playNext(queue: [])

        #expect(player.queue.count == 1)
    }
}

// MARK: - Skip / Back

struct PlayerNavigationTests {

    @Test func skipAdvancesIndex() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 0)

        player.skip()

        #expect(player.currentIndex == 1)
    }

    @Test func skipAtEndWithRepeatAllWraps() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 1)
        player.repeatMode = .all

        player.skip()

        #expect(player.currentIndex == 0)
    }

    @Test func skipAtEndWithRepeatOffStops() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 1)
        player.repeatMode = .off

        player.skip()

        #expect(player.isPlaying == false)
    }

    @Test func backGoesToPreviousWhenProgressLow() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 1)
        player.progress = 1.0 // Under 3s threshold

        player.back()

        #expect(player.currentIndex == 0)
    }

    @Test func skipToJumpsToIndex() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 0)

        player.skipTo(queueIndex: 2)

        #expect(player.currentIndex == 2)
    }

    @Test func skipToOutOfBoundsNoOp() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A")]
        player.playNow(queue: items, startingAt: 0)

        player.skipTo(queueIndex: 5)

        #expect(player.currentIndex == 0)
    }

    @Test func canSkipTrueWhenNotAtEnd() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)

        #expect(player.canSkip)
    }

    @Test func canSkipFalseAtEndWithRepeatOff() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 1)
        player.repeatMode = .off

        #expect(!player.canSkip)
    }

    @Test func canSkipTrueAtEndWithRepeatAll() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 1)
        player.repeatMode = .all

        #expect(player.canSkip)
    }

    @Test func canGoBackFalseOnEmptyQueue() {
        let player = makePlayer()
        #expect(!player.canGoBack)
    }
}

// MARK: - Queue Manipulation

struct PlayerQueueManipulationTests {

    @Test func clearUpNextKeepsCurrent() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 0)

        player.clearUpNext()

        #expect(player.queue.count == 1)
        #expect(player.queue[0].track.name == "A")
    }

    @Test func removeFromQueueRemovesCorrectItem() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                     makeQueueItem(name: "C"), makeQueueItem(name: "D")]
        player.playNow(queue: items, startingAt: 0)

        // Remove first item in up-next (index 0 in up-next = queue index 1)
        player.removeFromQueue(at: IndexSet(integer: 0))

        #expect(player.queue.count == 3)
        #expect(player.queue.map(\.track.name) == ["A", "C", "D"])
    }
}

// MARK: - Effective Index

struct PlayerEffectiveIndexTests {

    @Test func effectiveIndexWithoutShuffle() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 1)

        #expect(player.effectiveIndex == 1)
    }

    @Test func effectiveIndexWithShuffle() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 1)
        player.toggleShuffle()

        // After toggle, currentIndex=0, shuffledIndices[0]=1 (the real index)
        #expect(player.effectiveIndex == 1)
    }
}

// MARK: - Repeat Mode

struct PlayerRepeatModeTests {

    @Test func cycleRepeatMode() {
        let player = makePlayer()
        player.repeatMode = .off

        player.cycleRepeatMode()
        #expect(player.repeatMode == .all)

        player.cycleRepeatMode()
        #expect(player.repeatMode == .one)

        player.cycleRepeatMode()
        #expect(player.repeatMode == .off)
    }

    @Test func skipWithRepeatOneReplays() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)
        player.repeatMode = .one

        player.skip()

        // Repeat one: index stays the same
        #expect(player.currentIndex == 0)
    }
}

// MARK: - Queue Confirmation

struct PlayerQueueConfirmationTests {

    @Test func requestPlayShowsConfirmationWhenMultipleAlbums() {
        let player = makePlayer()
        let album1 = UUID(), album2 = UUID()
        let items = [
            makeQueueItem(name: "A", albumId: album1),
            makeQueueItem(name: "B", albumId: album2),
        ]
        player.playNow(queue: items, startingAt: 0)
        // Simulate that currentTrack is set
        player.currentTrack = items[0].track

        var actionCalled = false
        player.requestPlay { actionCalled = true }

        #expect(player.showReplaceQueueConfirmation)
        #expect(!actionCalled)

        player.confirmPlay()
        #expect(actionCalled)
    }

    @Test func requestPlayExecutesImmediatelyWhenSingleAlbum() {
        let player = makePlayer()
        let albumId = UUID()
        let items = [
            makeQueueItem(name: "A", albumId: albumId),
            makeQueueItem(name: "B", albumId: albumId),
        ]
        player.playNow(queue: items, startingAt: 0)
        player.currentTrack = items[0].track

        var actionCalled = false
        player.requestPlay { actionCalled = true }

        #expect(actionCalled)
        #expect(!player.showReplaceQueueConfirmation)
    }

    @Test func cancelPlayClearsPending() {
        let player = makePlayer()
        let album1 = UUID(), album2 = UUID()
        let items = [
            makeQueueItem(name: "A", albumId: album1),
            makeQueueItem(name: "B", albumId: album2),
        ]
        player.playNow(queue: items, startingAt: 0)
        player.currentTrack = items[0].track

        var actionCalled = false
        player.requestPlay { actionCalled = true }
        player.cancelPlay()
        player.confirmPlay()

        #expect(!actionCalled)
    }
}
