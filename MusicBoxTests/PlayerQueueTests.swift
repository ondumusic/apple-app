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
    // Scratch snapshot file so queue tests don't touch the real playback state.
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("player-queue-tests/\(UUID().uuidString).json")
    return PlayerService(api: api, settings: settings, stateStore: PlaybackStateStore(fileURL: stateURL))
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

    @Test func playNextWhileShuffledInsertsAfterCurrentInShuffleOrder() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                     makeQueueItem(name: "C"), makeQueueItem(name: "D")]
        player.playShuffled(queue: items)

        // currentIndex is 0 in shuffle order
        let shuffledBefore = player.shuffledIndices!
        let currentReal = shuffledBefore[0]

        player.playNext(queue: [makeQueueItem(name: "X")])

        #expect(player.queue.count == 5)
        let shuffled = player.shuffledIndices!
        #expect(shuffled.count == 5)
        // Current track should still be at position 0
        #expect(shuffled[0] == currentReal)
        // The inserted track should be at position 1 in shuffle order (plays next)
        let nextRealIndex = shuffled[1]
        #expect(player.queue[nextRealIndex].track.name == "X")
    }

    @Test func playNextWhileShuffledMultipleItemsInsertInOrder() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playShuffled(queue: items)

        player.playNext(queue: [makeQueueItem(name: "X"), makeQueueItem(name: "Y")])

        #expect(player.queue.count == 5)
        let shuffled = player.shuffledIndices!
        // X and Y should be at positions 1 and 2 in shuffle order
        #expect(player.queue[shuffled[1]].track.name == "X")
        #expect(player.queue[shuffled[2]].track.name == "Y")
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

    @Test func clearUpNextWhileShuffled() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                     makeQueueItem(name: "C"), makeQueueItem(name: "D")]
        player.playShuffled(queue: items)

        let currentTrackName = player.queue[player.effectiveIndex].track.name
        player.clearUpNext()

        #expect(player.queue.count == 1)
        #expect(player.queue[0].track.name == currentTrackName)
        #expect(player.shuffledIndices == [0])
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

    @Test func removeFromQueueWhileShuffled() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                     makeQueueItem(name: "C"), makeQueueItem(name: "D")]
        player.playShuffled(queue: items)

        let countBefore = player.queue.count
        // Remove the first up-next item
        player.removeFromQueue(at: IndexSet(integer: 0))

        #expect(player.queue.count == countBefore - 1)
        #expect(player.shuffledIndices?.count == countBefore - 1)
    }

    @Test func moveQueueItemsReorders() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                     makeQueueItem(name: "C"), makeQueueItem(name: "D")]
        player.playNow(queue: items, startingAt: 0)

        // Move up-next index 2 (D) to index 0 (before B)
        player.moveQueueItems(from: IndexSet(integer: 2), to: 0)

        // Queue should be: A (current), D, B, C
        #expect(player.queue.map(\.track.name) == ["A", "D", "B", "C"])
    }

    @Test func moveQueueItemsWhileShuffled() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                     makeQueueItem(name: "C"), makeQueueItem(name: "D")]
        player.playShuffled(queue: items)

        let shuffledBefore = player.shuffledIndices!
        let currentReal = shuffledBefore[0]

        // Move up-next index 2 to index 0
        player.moveQueueItems(from: IndexSet(integer: 2), to: 0)

        let shuffledAfter = player.shuffledIndices!
        // Current track should still be first
        #expect(shuffledAfter[0] == currentReal)
        // Shuffle order should be rearranged in the up-next portion
        #expect(shuffledAfter.count == 4)
    }
}

// MARK: - canGoBack / canSkip Edge Cases

struct PlayerCanNavigateTests {

    @Test func canGoBackTrueWhenProgressOverThreshold() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)
        player.progress = 5.0 // Over 3s threshold

        #expect(player.canGoBack)
    }

    @Test func canGoBackFalseAtStartWithLowProgress() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)
        player.progress = 1.0

        #expect(!player.canGoBack)
    }

    @Test func canGoBackTrueAtMiddle() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")]
        player.playNow(queue: items, startingAt: 1)
        player.progress = 1.0

        #expect(player.canGoBack)
    }

    @Test func canSkipWithRepeatOne() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A")]
        player.playNow(queue: items, startingAt: 0)
        player.repeatMode = .one

        #expect(player.canSkip)
    }

    @Test func canSkipEmptyQueue() {
        let player = makePlayer()
        #expect(!player.canSkip)
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

    @Test func requestPlayShowsConfirmationForAHandBuiltQueue() {
        let player = makePlayer()
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)
        // Simulate that currentTrack is set
        player.currentTrack = items[0].track
        player.playNext(queue: [makeQueueItem(name: "C")])

        var actionCalled = false
        player.requestPlay { actionCalled = true }

        #expect(player.showReplaceQueueConfirmation)
        #expect(!actionCalled)

        player.confirmPlay()
        #expect(actionCalled)
    }

    /// Spanning several albums is no longer the trigger — only hand edits are, so a
    /// multi-album queue you didn't build plays straight through.
    @Test func requestPlayExecutesImmediatelyForAnUntouchedQueue() {
        let player = makePlayer()
        let items = [
            makeQueueItem(name: "A", albumId: UUID()),
            makeQueueItem(name: "B", albumId: UUID()),
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
        let items = [makeQueueItem(name: "A"), makeQueueItem(name: "B")]
        player.playNow(queue: items, startingAt: 0)
        player.currentTrack = items[0].track
        player.playNext(queue: [makeQueueItem(name: "C")])

        var actionCalled = false
        player.requestPlay { actionCalled = true }
        player.cancelPlay()
        player.confirmPlay()

        #expect(!actionCalled)
    }
}

// MARK: - Playback Failure

struct PlayerPlaybackFailureTests {

    @Test func startsWithNoErrorAndNotBuffering() {
        let player = makePlayer()

        #expect(player.playbackError == nil)
        #expect(!player.isBuffering)
    }

    @Test func playPauseRetriesInsteadOfResumingAfterAFailure() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")], startingAt: 0)
        player.isPlaying = false
        player.playbackError = "Couldn't reach the server to play this track."

        player.togglePlayPause()

        // Resuming would flip isPlaying synchronously; retrying goes through an async
        // reload instead, leaving it false at this point.
        #expect(!player.isPlaying)
    }

    @Test func pausingAWorkingTrackStillResumes() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")], startingAt: 0)
        player.isPlaying = true

        player.togglePlayPause()

        #expect(!player.isPlaying)
    }
}

// MARK: - Replace-Queue Confirmation

struct PlayerReplaceQueueTests {

    @Test func playingAFreshQueueDoesNotPrompt() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")], startingAt: 0)
        player.currentTrack = player.queue[0].track

        var played = false
        player.requestPlay { played = true }

        #expect(played)
        #expect(!player.showReplaceQueueConfirmation)
    }

    @Test func replacingAHandBuiltQueuePrompts() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")], startingAt: 0)
        player.currentTrack = player.queue[0].track
        player.addToEnd(queue: [makeQueueItem(name: "B")])

        var played = false
        player.requestPlay { played = true }

        #expect(!played)
        #expect(player.showReplaceQueueConfirmation)
    }

    @Test func aFreshQueueClearsTheHandBuiltFlag() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")], startingAt: 0)
        player.playNext(queue: [makeQueueItem(name: "B")])
        #expect(player.isQueueUserModified)

        player.playNow(queue: [makeQueueItem(name: "C")], startingAt: 0)

        #expect(!player.isQueueUserModified)
    }

    @Test func reorderingMarksTheQueueHandBuilt() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")], startingAt: 0)
        #expect(!player.isQueueUserModified)

        player.moveQueueItems(from: IndexSet(integer: 0), to: 2)

        #expect(player.isQueueUserModified)
    }
}

// MARK: - Up Next Ordering

struct PlayerUpNextTests {

    @Test func unshuffledUpNextFollowsQueueOrder() {
        let player = makePlayer()
        let items = (1...5).map { makeQueueItem(name: "T\($0)") }
        player.playNow(queue: items, startingAt: 1)

        #expect(player.upNextEntries.map(\.originalIndex) == [2, 3, 4])
    }

    /// The bug this covers: walking the raw queue and comparing against effectiveIndex
    /// dropped everything shuffle had placed before the current track.
    @Test func shuffledUpNextFollowsPlayOrderAndKeepsEveryTrack() {
        let player = makePlayer()
        let items = (1...5).map { makeQueueItem(name: "T\($0)") }
        player.playNow(queue: items, startingAt: 0)
        player.shuffledIndices = [3, 0, 4, 1, 2]
        player.currentIndex = 0

        // Everything after position 0 in play order — not queue positions after index 3.
        #expect(player.upNextEntries.map(\.originalIndex) == [0, 4, 1, 2])
        #expect(player.upNextEntries.count == items.count - 1)
    }

    @Test func upNextIsEmptyOnTheLastTrack() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A"), makeQueueItem(name: "B")], startingAt: 1)

        #expect(player.upNextEntries.isEmpty)
    }
}
