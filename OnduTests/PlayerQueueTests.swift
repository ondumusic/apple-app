import AVFoundation
import Foundation
import Testing

@testable import Ondu

// MARK: - Helpers

private let testArtist = Artist(id: UUID(), name: "Artist", sortName: "Artist", slug: "artist")

private func makeTrack(
    name: String = "Track", albumId: UUID = UUID(),
    disc: Int = 1, number: Int = 1
) -> Track {
    Track(
        id: UUID(), artistId: testArtist.id, albumArtistId: testArtist.id,
        albumId: albumId, artist: testArtist, albumArtistSortName: testArtist.sortName,
        name: name, disc: disc, number: number, duration: 200,
        mimetype: "audio/mp4", streamUrl: "/stream/test")
}

private func makeQueueItem(
    name: String = "Track", albumId: UUID = UUID(),
    disc: Int = 1, number: Int = 1
) -> QueueItem {
    QueueItem(track: makeTrack(name: name, albumId: albumId, disc: disc, number: number))
}

private func makePlayer() -> PlayerService {
    let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
    let settings = makeTestSettings()
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
        let items = [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ]
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
        player.progress = 1.0  // Under 3s threshold

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
        let items = [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ]
        player.playShuffled(queue: items)

        let currentTrackName = player.queue[player.effectiveIndex].track.name
        player.clearUpNext()

        #expect(player.queue.count == 1)
        #expect(player.queue[0].track.name == currentTrackName)
        #expect(player.shuffledIndices == [0])
    }

    @Test func removeFromQueueRemovesCorrectItem() {
        let player = makePlayer()
        let items = [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ]
        player.playNow(queue: items, startingAt: 0)

        // Remove first item in up-next (index 0 in up-next = queue index 1)
        player.removeFromQueue(at: IndexSet(integer: 0))

        #expect(player.queue.count == 3)
        #expect(player.queue.map(\.track.name) == ["A", "C", "D"])
    }

    @Test func removeFromQueueWhileShuffled() {
        let player = makePlayer()
        let items = [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ]
        player.playShuffled(queue: items)

        let countBefore = player.queue.count
        // Remove the first up-next item
        player.removeFromQueue(at: IndexSet(integer: 0))

        #expect(player.queue.count == countBefore - 1)
        #expect(player.shuffledIndices?.count == countBefore - 1)
    }

    @Test func moveQueueItemsReorders() {
        let player = makePlayer()
        let items = [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ]
        player.playNow(queue: items, startingAt: 0)

        // Move up-next index 2 (D) to index 0 (before B)
        player.moveQueueItems(from: IndexSet(integer: 2), to: 0)

        // Queue should be: A (current), D, B, C
        #expect(player.queue.map(\.track.name) == ["A", "D", "B", "C"])
    }

    @Test func moveQueueItemsWhileShuffled() {
        let player = makePlayer()
        let items = [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ]
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
        player.progress = 5.0  // Over 3s threshold

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

    /// AVFoundation's own message for a stream it couldn't open, which is what a refused
    /// token produces.
    private static let streamFailure = "Cannot Open"

    private func failingStream(_ player: PlayerService) -> AVPlayerItem {
        let item = AVPlayerItem(url: URL(string: "https://music.example.com/stream/1")!)
        player.currentPlayerItem = item
        return item
    }

    @Test func aRefusedStreamWithAnExpiredSessionAsksToSignIn() async {
        let player = makePlayer()
        player.sessionCheckOverride = { true }
        var expiries = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .sessionExpired, object: nil, queue: nil
        ) { _ in expiries += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        await player.failStream(failingStream(player), message: Self.streamFailure)

        #expect(player.playbackError == "Your session expired. Sign in again to keep listening.")
        #expect(expiries == 1)
    }

    @Test func signingBackInResumesWhatTheExpiryStopped() async {
        let player = makePlayer()
        player.queue = [makeQueueItem(name: "A")]
        player.sessionCheckOverride = { true }
        await player.failStream(failingStream(player), message: Self.streamFailure)
        #expect(player.resumesAfterSignIn)

        player.update(api: APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "new"))

        #expect(!player.resumesAfterSignIn)
    }

    @Test func signingInAfterAnUnrelatedFailureDoesNotStartPlayback() async {
        let player = makePlayer()
        player.queue = [makeQueueItem(name: "A")]
        player.sessionCheckOverride = { false }

        await player.failStream(failingStream(player), message: Self.streamFailure)

        #expect(!player.resumesAfterSignIn)
    }

    @Test func clearingTheQueueAfterAnExpiryCancelsTheResume() async {
        let player = makePlayer()
        player.queue = [makeQueueItem(name: "A")]
        player.sessionCheckOverride = { true }
        await player.failStream(failingStream(player), message: Self.streamFailure)

        player.stopAndClear()

        #expect(!player.resumesAfterSignIn)
    }

    @Test func aRefusedStreamWithAValidSessionKeepsItsOwnMessage() async {
        let player = makePlayer()
        player.sessionCheckOverride = { false }

        await player.failStream(failingStream(player), message: Self.streamFailure)

        #expect(player.playbackError == Self.streamFailure)
    }

    @Test func anAnswerForATrackSinceSkippedChangesNothing() async {
        let player = makePlayer()
        player.sessionCheckOverride = { true }
        let stale = failingStream(player)
        _ = failingStream(player)

        await player.failStream(stale, message: Self.streamFailure)

        #expect(player.playbackError == nil)
    }

    @Test func anUnplayableCachedCopyIsForgottenSoTheRetryStreams() {
        let player = makePlayer()
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        var item = makeQueueItem(name: "A")
        item.playbackURL = bad
        player.queue = [item, makeQueueItem(name: "B")]

        player.forgetUnplayableCopy(at: bad)

        #expect(player.queue[0].playbackURL == nil)
    }

    @Test func aTranscodedStreamsEstimateDoesNotReplaceTheTracksDuration() {
        #expect(PlayerService.measuredDuration(0.4, known: 245) == nil)
    }

    @Test func theItemsDurationFillsInWhenTheTrackHasNone() {
        #expect(PlayerService.measuredDuration(245, known: 0) == 245)
        #expect(PlayerService.measuredDuration(245, known: nil) == 245)
        #expect(PlayerService.measuredDuration(.nan, known: 0) == nil)
    }

    @Test func theFadeStartsInsideItsWindowAndNotBefore() {
        #expect(PlayerService.crossfadeRemaining(duration: 200, current: 180, fadeDuration: 12) == nil)
        #expect(PlayerService.crossfadeRemaining(duration: 200, current: 190, fadeDuration: 12) == 10)
        #expect(PlayerService.crossfadeRemaining(duration: 200, current: 200.5, fadeDuration: 12) == nil)
    }

    @Test func theFadeWaitsForADurationItCanTrust() {
        #expect(PlayerService.crossfadeRemaining(duration: 0, current: 5, fadeDuration: 12) == nil)
        #expect(PlayerService.crossfadeRemaining(duration: .nan, current: 5, fadeDuration: 12) == nil)
    }

    /// Only time spent playing counts: a pause in the middle of a fade must not finish it.
    @Test func aFadeOnlyAdvancesWhilePlaying() {
        var ramp = PlayerService.CrossfadeRamp(
            fadeDuration: 12, nextIndex: 1, nextTrack: makeQueueItem(name: "B").track)
        ramp.advance(by: 3)
        #expect(ramp.fraction == 0.25)
        #expect(!ramp.isComplete)
        ramp.advance(by: 9)
        #expect(ramp.fraction == 1)
        #expect(ramp.isComplete)
    }

    @Test func aGaplessAdvanceTheAppDidNotFollowIsCaught() {
        let previous = AVPlayerItem(url: URL(string: "https://music.example.com/stream/1")!)
        let queued = AVPlayerItem(url: URL(string: "https://music.example.com/stream/2")!)

        #expect(PlayerService.hasMissedGaplessAdvance(playing: queued, tracked: previous, queued: queued))
    }

    @Test func aFollowedOrUnqueuedItemIsNotAMissedAdvance() {
        let previous = AVPlayerItem(url: URL(string: "https://music.example.com/stream/1")!)
        let queued = AVPlayerItem(url: URL(string: "https://music.example.com/stream/2")!)

        // Still on the previous track, as before the boundary.
        #expect(!PlayerService.hasMissedGaplessAdvance(playing: previous, tracked: previous, queued: queued))
        // The app followed: the queued item is now the tracked one.
        #expect(!PlayerService.hasMissedGaplessAdvance(playing: queued, tracked: queued, queued: queued))
        // Nothing queued for gapless.
        #expect(!PlayerService.hasMissedGaplessAdvance(playing: queued, tracked: previous, queued: nil))
    }

    @Test func aStreamCutOffInItsLastSecondsCountsAsFinished() {
        #expect(PlayerService.isEffectivelyFinished(remaining: 2))
        #expect(PlayerService.isEffectivelyFinished(remaining: 0))
        #expect(!PlayerService.isEffectivelyFinished(remaining: 60))
    }

    @Test func stopLeavesNothingLoaded() {
        let player = makePlayer()
        let album = UUID()
        player.queue = [
            makeQueueItem(name: "A", albumId: album, number: 1),
            makeQueueItem(name: "B", albumId: album, number: 2),
        ]
        player.currentPlayerItem = AVPlayerItem(url: URL(string: "https://music.example.com/stream/1")!)

        player.stopAndClear()

        #expect(player.currentPlayerItem == nil)
        #expect(player.queue.isEmpty)
    }

    @Test func playPauseDoesNothingWithAnEmptyQueue() {
        let player = makePlayer()
        player.stopAndClear()

        player.togglePlayPause()

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
        player.playNow(
            queue: [makeQueueItem(name: "A"), makeQueueItem(name: "B"), makeQueueItem(name: "C")], startingAt: 0)
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

// MARK: - History

/// Queue A,B,C,D shuffled to play D,B,A,C, stopped on A — so B and D are history and
/// C is still to come.
@MainActor
private func shuffledPlayerMidway() -> PlayerService {
    let player = makePlayer()
    player.playNow(
        queue: [
            makeQueueItem(name: "A"), makeQueueItem(name: "B"),
            makeQueueItem(name: "C"), makeQueueItem(name: "D"),
        ],
        startingAt: 0)
    player.shuffledIndices = [3, 1, 0, 2]
    player.currentIndex = 2
    return player
}

@MainActor
struct PlayerHistoryTests {

    @Test func historyIsWhatPlayedMostRecentFirst() {
        let player = makePlayer()
        player.playNow(
            queue: [
                makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                makeQueueItem(name: "C"), makeQueueItem(name: "D"),
            ],
            startingAt: 2)

        #expect(player.historyEntries.map(\.item.track.name) == ["B", "A"])
        #expect(player.upNextEntries.map(\.item.track.name) == ["D"])
    }

    @Test func nothingPlayedYetMeansNoHistory() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A"), makeQueueItem(name: "B")], startingAt: 0)

        #expect(player.historyEntries.isEmpty)
    }

    /// History reads in the order the shuffle actually played, not queue order.
    @Test func historyFollowsTheShuffleOrder() {
        let player = makePlayer()
        player.playNow(
            queue: [
                makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                makeQueueItem(name: "C"),
            ],
            startingAt: 0)
        player.shuffledIndices = [2, 0, 1]
        player.currentIndex = 2

        #expect(player.historyEntries.map(\.item.track.name) == ["A", "C"])
    }

    @Test func clearHistoryDropsWhatPlayedAndKeepsTheRest() {
        let player = makePlayer()
        player.playNow(
            queue: [
                makeQueueItem(name: "A"), makeQueueItem(name: "B"),
                makeQueueItem(name: "C"),
            ],
            startingAt: 2)
        player.clearHistory()

        #expect(player.queue.map(\.track.name) == ["C"])
        #expect(player.currentIndex == 0)
        #expect(player.historyEntries.isEmpty)
    }

    /// The played entries have to leave `queue` itself, not just the shuffle map —
    /// otherwise a later reshuffle would deal them back in.
    @Test func clearHistoryRebuildsTheShuffleMapQueue() {
        let player = shuffledPlayerMidway()
        player.clearHistory()
        #expect(player.queue.map(\.track.name).sorted() == ["A", "C"])
    }

    @Test func clearHistoryRebuildsTheShuffleMapIndex() {
        let player = shuffledPlayerMidway()
        player.clearHistory()
        #expect(player.currentIndex == 0)
        #expect(player.shuffledIndices?.count == 2)
    }

    @Test func clearHistoryKeepsWhatComesNext() {
        let player = shuffledPlayerMidway()
        player.clearHistory()
        #expect(player.upNextEntries.map(\.item.track.name) == ["C"])
    }
}

// MARK: - Sign Out

/// Used by sign-out, where nothing else stops the player because the mini player window
/// keeps it alive, and by Controls ▸ Stop.
struct PlayerStopTests {

    @Test func emptiesTheQueue() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A"), makeQueueItem(name: "B")])
        player.stopAndClear()
        #expect(player.queue.isEmpty)
        #expect(player.currentTrack == nil)
        #expect(player.currentIndex == 0)
    }

    @Test func stopsPlayback() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A")])
        player.stopAndClear()
        #expect(!player.isPlaying)
        #expect(player.progress == 0)
    }

    @Test func dropsShuffle() {
        let player = makePlayer()
        player.playNow(queue: [makeQueueItem(name: "A"), makeQueueItem(name: "B")])
        player.shuffledIndices = [1, 0]
        player.stopAndClear()
        #expect(player.shuffledIndices == nil)
    }
}

// MARK: - Artwork tinting

/// The players wear the current cover; with nothing playing there's nothing to wear, and
/// dressing for a tint that isn't there leaves white controls on a plain background.
struct PlayerTintTests {

    private func makePlayer(_ settings: SettingsStore) -> PlayerService {
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-tint-tests/\(UUID().uuidString).json")
        return PlayerService(
            api: api, settings: settings,
            stateStore: PlaybackStateStore(fileURL: stateURL))
    }

    private func tintedSettings() -> SettingsStore {
        let settings = makeTestSettings()
        settings.artworkTintedPlayer = true
        return settings
    }

    private func itemWithArtwork() -> QueueItem {
        var item = makeQueueItem(name: "A")
        item.artworkURL = URL(string: "https://example.com/cover.jpg")
        return item
    }

    @Test func doesNotTintWithAnEmptyQueue() {
        #expect(!makePlayer(tintedSettings()).tintsFromArtwork)
    }

    @Test func doesNotTintATrackWithNoArtwork() {
        let player = makePlayer(tintedSettings())
        player.playNow(queue: [makeQueueItem(name: "A")])
        #expect(player.currentArtworkURL == nil)
        #expect(!player.tintsFromArtwork)
    }

    @Test func tintsWhenTheTrackHasArtwork() {
        let player = makePlayer(tintedSettings())
        player.playNow(queue: [itemWithArtwork()])
        #expect(player.tintsFromArtwork)
    }

    @Test func doesNotTintWhenTheSettingIsOff() {
        let settings = tintedSettings()
        let player = makePlayer(settings)
        player.playNow(queue: [itemWithArtwork()])
        settings.artworkTintedPlayer = false
        #expect(!player.tintsFromArtwork)
    }
}

// MARK: - Stale Indices

struct PlayerStaleIndexTests {

    /// `loadAndPlayCurrent` resolves the current index, awaits the prefetch, then hands
    /// off to the gapless setup — so the queue can shrink under an index that was in
    /// range when it was taken. The shuffle order is left behind as the wider one.
    @Test func gaplessSetupSurvivesAShuffleOrderWiderThanTheQueue() {
        let player = makePlayer()
        let album = UUID()
        player.queue = [
            makeQueueItem(name: "A", albumId: album, number: 1),
            makeQueueItem(name: "B", albumId: album, number: 2),
        ]
        player.shuffledIndices = [5, 1]
        player.currentIndex = 0

        player.cycleRepeatMode()

        #expect(player.queue.count == 2)
    }

    @Test func nowPlayingSurvivesAShuffleOrderWiderThanTheQueue() {
        let player = makePlayer()
        player.queue = [makeQueueItem(name: "A")]
        player.shuffledIndices = [7]
        player.currentIndex = 0

        #expect(player.currentArtworkURL == nil)
    }
}
