import AVFoundation
import MediaPlayer
import Nuke
import SwiftUI

nonisolated enum RepeatMode: String, Sendable {
    case off, one, all
}

@Observable
final class PlayerService {
    // MARK: - Public state

    var queue: [QueueItem] = [] {
        didSet { queueIsSingleAlbum = Self.isSingleAlbum(queue) }
    }
    /// Whether the whole queue is one album, which is what picks album gain over track
    /// gain. Recomputed on every queue mutation rather than per track change — it is a
    /// linear scan either way, and this way the answer is ready when a track starts.
    @ObservationIgnored private var queueIsSingleAlbum = false
    var currentIndex: Int = 0
    var shuffledIndices: [Int]? = nil
    var repeatMode: RepeatMode = .off
    var isPlaying: Bool = false
    var currentTrack: Track? = nil {
        didSet {
            guard currentTrack?.id != oldValue?.id else { return }
            listenedSeconds = 0
            lastProgressSample = nil
            hasReportedCurrentPlay = false
            playStartedAt = currentTrack == nil ? nil : Date()
        }
    }
    var progress: Double = 0
    var duration: Double = 0
    var queueConfirmation: QueueConfirmation? = nil
    /// Set when playback stops for a reason the user should see. An item that fails or
    /// never becomes ready is otherwise indistinguishable from one that just started.
    var playbackError: String? = nil
    /// True once the user has shaped this queue by hand — Play Next, Add to Queue,
    /// reorder, remove. Replacing a queue you built is worth confirming; replacing one
    /// that is just "the album I pressed play on" is not.
    private(set) var isQueueUserModified: Bool = false
    /// True while a track is being prepared — a stream can take seconds to buffer.
    private(set) var isBuffering: Bool = false
    /// Output volume, 0...1. Scales everything the crossfade ramp does rather than
    /// competing with it, so a fade still lands at the level the user chose.
    var volume: Double = 1.0 {
        didSet {
            settings.volume = volume
            applyVolume()
        }
    }
    /// Loudness-normalisation multipliers for the track each player is holding. They are
    /// per-player because a crossfade has two different tracks in the air at once.
    @ObservationIgnored private(set) var primaryGain: Float = 1
    @ObservationIgnored private var secondaryGain: Float = 1
    var showReplaceQueueConfirmation: Bool = false
    @ObservationIgnored private var pendingPlayAction: (() -> Void)?

    nonisolated enum QueueConfirmation: Equatable, Sendable {
        case playNext(Int)
        case addedToQueue(Int)
    }

    func requestPlay(_ action: @escaping () -> Void) {
        if currentTrack != nil && isQueueUserModified {
            pendingPlayAction = action
            showReplaceQueueConfirmation = true
        } else {
            action()
        }
    }

    func confirmPlay() {
        pendingPlayAction?()
        pendingPlayAction = nil
    }

    func cancelPlay() {
        pendingPlayAction = nil
    }

    var isShuffled: Bool { shuffledIndices != nil }

    /// Everything queued after the current track, in the order it will actually play —
    /// which is the shuffled order when shuffle is on. Walking the raw queue and
    /// comparing against `effectiveIndex` instead drops whatever shuffle placed earlier
    /// and lists the rest in the wrong order.
    /// What has already played, most recent first — the same walk as `upNextEntries`
    /// but backwards from the current track, so it reads in shuffle order too.
    var historyEntries: [(originalIndex: Int, item: QueueItem)] {
        guard !queue.isEmpty, currentIndex > 0 else { return [] }
        return (0..<currentIndex).reversed().compactMap { position in
            let effective: Int
            if let shuffled = shuffledIndices, position < shuffled.count {
                effective = shuffled[position]
            } else {
                effective = position
            }
            guard queue.indices.contains(effective) else { return nil }
            return (effective, queue[effective])
        }
    }

    var upNextEntries: [(originalIndex: Int, item: QueueItem)] {
        guard !queue.isEmpty, currentIndex >= 0 else { return [] }
        let start = currentIndex + 1
        guard start < queue.count else { return [] }
        return (start..<queue.count).compactMap { position in
            let effective: Int
            if let shuffled = shuffledIndices, position < shuffled.count {
                effective = shuffled[position]
            } else {
                effective = position
            }
            guard queue.indices.contains(effective) else { return nil }
            return (effective, queue[effective])
        }
    }

    // MARK: - Private

    @ObservationIgnored private var api: APIService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let musicLibrary: MusicLibrary?
    @ObservationIgnored private let playbackCache: PlaybackCache?
    @ObservationIgnored private let stateStore: PlaybackStateStore
    @ObservationIgnored private var lastPositionSave: Date = .distantPast
    /// Position to resume at, from a restored snapshot. Keyed by track so a skip before
    /// the first play doesn't seek the wrong track.
    @ObservationIgnored private var pendingResume: (trackId: UUID, time: Double)?
    @ObservationIgnored private var primaryPlayer = AVQueuePlayer()
    @ObservationIgnored private var secondaryPlayer: AVQueuePlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var crossfadeObserver: Any?
    @ObservationIgnored private var crossfadeTimer: Timer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var nowPlayingArtworkURL: URL?
    @ObservationIgnored private var isSeeking: Bool = false

    // MARK: - Play reporting

    /// Where finished listens go. Set by the app whenever there's a session to report to.
    @ObservationIgnored var outbox: OutboxService?
    /// Real listening, accumulated from playback deltas rather than position, so seeking
    /// to the end doesn't count as having heard it.
    @ObservationIgnored private var listenedSeconds: Double = 0
    @ObservationIgnored private var lastProgressSample: Double?
    @ObservationIgnored private var playStartedAt: Date?
    @ObservationIgnored private var hasReportedCurrentPlay = false
    /// How much of a track has to be heard before it counts as played.
    nonisolated enum PlayThreshold {
        /// However long the track runs, four minutes of it is enough.
        static let cap: Double = 240

        /// Half the track or the cap, whichever comes first — the scrobbling convention.
        /// Skipping through an album reports nothing.
        static func seconds(forDuration duration: Double) -> Double {
            guard duration > 0 else { return cap }
            return min(duration / 2, cap)
        }
    }
    @ObservationIgnored private var isLoadingTrack: Bool = false
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var stallWatchdog: Task<Void, Never>?
    /// The deferred queue restore. Exposed so tests can await it — the app never needs to.
    @ObservationIgnored private(set) var restoreTask: Task<Void, Never>?
    /// How long a remote item may sit un-ready before we call it failed. A rejected token
    /// produces no error and no timeout of its own — it simply never becomes ready.
    private static let stallTimeout: TimeInterval = 15
    /// Tracks whether AVQueuePlayer has a queued next item for gapless playback
    @ObservationIgnored private var hasQueuedGaplessItem: Bool = false
    /// The AVPlayerItem currently playing — used to filter endObserver notifications
    @ObservationIgnored private var currentPlayerItem: AVPlayerItem?
    /// The AVPlayerItem queued for gapless playback
    @ObservationIgnored private var gaplessPlayerItem: AVPlayerItem?

    // MARK: - Computed

    /// The cover the players should dress themselves in, if there is one.
    var currentArtworkURL: URL? {
        guard queue.indices.contains(effectiveIndex) else { return nil }
        return queue[effectiveIndex].artworkURL
    }

    /// Whether the players wear the artwork. Both halves matter: the setting is the
    /// user's choice, and a cover has to exist for there to be anything to wear. With
    /// nothing playing the players dress as if the setting were off — white-on-nothing
    /// is the alternative.
    var tintsFromArtwork: Bool {
        settings.artworkTintedPlayer && currentArtworkURL != nil
    }

    var effectiveIndex: Int {
        if let shuffled = shuffledIndices {
            guard currentIndex >= 0 && currentIndex < shuffled.count else { return 0 }
            return shuffled[currentIndex]
        }
        return currentIndex
    }

    var canSkip: Bool {
        guard !queue.isEmpty else { return false }
        if repeatMode == .one || repeatMode == .all { return true }
        return currentIndex + 1 < queue.count
    }

    var canGoBack: Bool {
        guard !queue.isEmpty else { return false }
        if progress > 3 { return true }
        return currentIndex > 0
    }

    // MARK: - Init

    init(api: APIService, settings: SettingsStore, musicLibrary: MusicLibrary? = nil,
         playbackCache: PlaybackCache? = nil, stateStore: PlaybackStateStore = PlaybackStateStore()) {
        self.api = api
        self.settings = settings
        self.musicLibrary = musicLibrary
        self.playbackCache = playbackCache
        self.stateStore = stateStore
        self.repeatMode = settings.repeatMode
        self.volume = settings.volume
        applyVolume()
        setupTimeObserver()
        setupEndObserver()
        setupAudioSession()
        setupRemoteCommands()
        // Off the first-frame path: nothing on screen needs the saved queue, and
        // resolving it here made launch scale with however many tracks were queued.
        restoreTask = Task { @MainActor [weak self] in self?.restoreState() }
        settings.onNormalizeVolumeChange = { [weak self] in self?.refreshNormalization() }
    }

    private func applyVolume() {
        primaryPlayer.volume = Float(volume) * primaryGain
        secondaryPlayer?.volume = Float(volume) * secondaryGain
    }

    /// One track on its own is not "listening to an album" — you asked for that song, so
    /// it gets levelled like any other single song.
    private static func isSingleAlbum(_ items: [QueueItem]) -> Bool {
        guard items.count > 1, let first = items.first?.track.albumId else { return false }
        return items.allSatisfy { $0.track.albumId == first }
    }

    /// The normalisation multiplier for a track.
    ///
    /// Album gain when the queue is one album: an album's quiet tracks are quiet on
    /// purpose, and flattening them is exactly what album gain exists to prevent. Any
    /// other queue is one the user assembled, where every track at the same level is the
    /// point.
    private func normalizationGain(for track: Track) -> Float {
        guard settings.normalizeVolume else { return 1 }
        if queueIsSingleAlbum, let albumLUFS = musicLibrary?.albumLUFS(for: track.albumId) {
            return LoudnessNormalization.gain(forLUFS: albumLUFS)
        }
        return LoudnessNormalization.gain(forLUFS: track.lufs)
    }

    /// Re-applies normalisation to whatever is playing now. Called when the setting
    /// changes, so it takes effect mid-track instead of at the next boundary.
    func refreshNormalization() {
        primaryGain = currentTrack.map(normalizationGain(for:)) ?? 1
        applyVolume()
    }

    /// Adopts a freshly minted API service after re-auth. Rebuilding the player instead
    /// would drop the queue and stop playback mid-track.
    func update(api: APIService) {
        self.api = api
        // Any item already queued for gapless carries the old bearer token.
        invalidateGaplessState()
    }

    deinit {
        stallWatchdog?.cancel()
        itemStatusObservation?.invalidate()
        if let timeObserver { primaryPlayer.removeTimeObserver(timeObserver) }
        if let crossfadeObserver { primaryPlayer.removeTimeObserver(crossfadeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
        crossfadeTimer?.invalidate()
    }

    // MARK: - Queue Operations

    func playNow(tracks: [Track], startingAt index: Int = 0, artworkURL: URL? = nil) {
        queue = tracks.map { QueueItem(track: $0, artworkURL: artworkURL ?? $0.album?.artworkUrl) }
        shuffledIndices = nil
        currentIndex = index
        isQueueUserModified = false
        savePlaybackState()
        Task { await loadAndPlayCurrent() }
    }

    func playNow(queue items: [QueueItem], startingAt index: Int = 0) {
        queue = items
        shuffledIndices = nil
        currentIndex = index
        isQueueUserModified = false
        savePlaybackState()
        Task { await loadAndPlayCurrent() }
    }

    func playShuffled(tracks: [Track], artworkURL: URL? = nil) {
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL ?? $0.album?.artworkUrl) }
        playShuffled(queue: items)
    }

    func playShuffled(queue items: [QueueItem]) {
        guard !items.isEmpty else { return }
        queue = items
        shuffledIndices = SmartShuffle.shuffledIndices(for: items, spread: settings.spreadShuffle)
        currentIndex = 0
        isQueueUserModified = false
        savePlaybackState()
        Task { await loadAndPlayCurrent() }
    }

    func playNext(tracks: [Track], artworkURL: URL? = nil) {
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL ?? $0.album?.artworkUrl) }
        playNext(queue: items)
    }

    func playNext(queue items: [QueueItem]) {
        guard !items.isEmpty else { return }
        if queue.isEmpty {
            playNow(queue: items)
            return
        }
        let insertIndex = min(effectiveIndex + 1, queue.count)
        queue.insert(contentsOf: items, at: insertIndex)
        if var shuffled = shuffledIndices {
            // Shift existing indices that are at or past the insert point
            shuffled = shuffled.map { $0 >= insertIndex ? $0 + items.count : $0 }
            // Insert new indices right after current position in shuffle order
            let newIndices = items.indices.map { insertIndex + $0 }
            let shuffleInsertPos = currentIndex + 1
            shuffled.insert(contentsOf: newIndices, at: shuffleInsertPos)
            shuffledIndices = shuffled
        }
        isQueueUserModified = true
        queueConfirmation = .playNext(items.count)
        invalidateGaplessState()
        savePlaybackState()
    }

    /// Inserts at a position within up-next, where 0 is "plays next" and `upNextEntries.count`
    /// is the end of the queue.
    ///
    /// The position is an offset into the up-next slice, matching moveQueueItems and
    /// removeFromQueue — not an index into `queue`, which is what `upNextEntries` reports.
    func insertIntoQueue(_ items: [QueueItem], at position: Int) {
        guard !items.isEmpty else { return }
        if queue.isEmpty {
            playNow(queue: items)
            return
        }
        let nextBefore = upcomingTrackId
        let slot = max(0, min(position, upNextEntries.count))

        if var shuffled = shuffledIndices {
            // Shuffled: the new items go on the end of `queue` and their positions are
            // spliced into the shuffle order, since that's what decides play order.
            let appendIndex = queue.count
            queue.append(contentsOf: items)
            let newIndices = items.indices.map { appendIndex + $0 }
            shuffled.insert(contentsOf: newIndices, at: min(currentIndex + 1 + slot, shuffled.count))
            shuffledIndices = shuffled
        } else {
            let insertIndex = min(currentIndex + 1 + slot, queue.count)
            queue.insert(contentsOf: items, at: insertIndex)
        }

        isQueueUserModified = true
        if upcomingTrackId != nextBefore { invalidateGaplessState() }
        savePlaybackState()
    }

    func addToEnd(tracks: [Track], artworkURL: URL? = nil) {
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL ?? $0.album?.artworkUrl) }
        addToEnd(queue: items)
    }

    func addToEnd(queue items: [QueueItem]) {
        guard !items.isEmpty else { return }
        if queue.isEmpty {
            playNow(queue: items)
            return
        }
        let startIndex = queue.count
        queue.append(contentsOf: items)
        if var shuffled = shuffledIndices {
            let newIndices = items.indices.map { startIndex + $0 }
            shuffled += newIndices
            shuffledIndices = shuffled
        }
        isQueueUserModified = true
        queueConfirmation = .addedToQueue(items.count)
        savePlaybackState()
    }

    func skip() {
        let count = queue.count
        guard count > 0 else { return }

        if repeatMode == .one {
            Task { await loadAndPlayCurrent() }
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < count {
            currentIndex = nextIndex
            Task { await loadAndPlayCurrent() }
        } else if repeatMode == .all {
            currentIndex = 0
            Task { await loadAndPlayCurrent() }
        } else {
            isPlaying = false
            primaryPlayer.pause()
            primaryPlayer.removeAllItems()
            tearDownCrossfade()
            hasQueuedGaplessItem = false
            currentPlayerItem = nil
            gaplessPlayerItem = nil
            currentIndex = 0
            let idx = effectiveIndex
            if idx < queue.count {
                currentTrack = queue[idx].track
                duration = queue[idx].track.duration
            }
            progress = 0
            updateNowPlayingInfo()
            updateNowPlayingPlaybackState()
            savePlaybackState()
        }
    }

    func skipTo(queueIndex: Int) {
        guard queueIndex >= 0 && queueIndex < queue.count else { return }
        currentIndex = queueIndex
        Task { await loadAndPlayCurrent() }
    }

    func back() {
        guard !queue.isEmpty else { return }
        if progress > 3 {
            seek(to: 0)
        } else {
            let prevIndex = currentIndex - 1
            if prevIndex >= 0 {
                currentIndex = prevIndex
                Task { await loadAndPlayCurrent() }
            } else {
                seek(to: 0)
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            primaryPlayer.pause()
            isPlaying = false
            let currentTime = primaryPlayer.currentTime().seconds
            if currentTime.isFinite {
                progress = currentTime
            }
        } else if (primaryPlayer.currentItem == nil || playbackError != nil) && !queue.isEmpty {
            // Retry rather than resume: the existing item is either absent or one the
            // player already rejected, and calling play() on it just fails silently.
            Task { await loadAndPlayCurrent() }
            return
        } else {
            primaryPlayer.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
        savePlaybackPosition()
    }

    /// Resume only if paused. The remote `play` command arrives while playing more often
    /// than you'd think — a headset button, another app handing back an interruption —
    /// and toggling on it pauses the music the caller just asked to hear.
    func resumePlayback() {
        guard !isPlaying else { return }
        togglePlayPause()
    }

    func pausePlayback() {
        guard isPlaying else { return }
        togglePlayPause()
    }

    /// Stops everything, because the account this queue came from is gone.
    ///
    /// Not left to deinit: on macOS the mini player window holds the player after the
    /// app has dropped its own reference, so without this it plays on against a library
    /// and a token that no longer exist — the buffered track and the one queued behind
    /// it for gapless still play, and everything after them fails.
    func stopForSignOut() {
        primaryPlayer.pause()
        primaryPlayer.removeAllItems()
        tearDownCrossfade()
        invalidateGaplessState()
        queue = []
        shuffledIndices = nil
        currentIndex = 0
        currentTrack = nil
        isPlaying = false
        isQueueUserModified = false
        progress = 0
        duration = 0
        playbackError = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    func seek(to time: Double) {
        isSeeking = true
        progress = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        primaryPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isSeeking = false
        }
        updateNowPlayingElapsed()
    }

    func clearUpNext() {
        let keep = currentIndex + 1
        if let shuffled = shuffledIndices {
            let keptRealIndices = Array(shuffled.prefix(keep))
            let sortedKept = keptRealIndices.sorted()
            var oldToNew: [Int: Int] = [:]
            for (newIdx, oldIdx) in sortedKept.enumerated() {
                oldToNew[oldIdx] = newIdx
            }
            queue = sortedKept.map { queue[$0] }
            shuffledIndices = keptRealIndices.map { oldToNew[$0]! }
        } else {
            queue = Array(queue.prefix(keep))
        }
        isQueueUserModified = true
        invalidateGaplessState()
        savePlaybackState()
    }

    /// Drops everything before the current track. Mirrors clearUpNext from the other
    /// side, including the shuffle map rebuild — the played entries have to come out of
    /// `queue` itself, not just out of the map, or they'd come back on the next shuffle.
    func clearHistory() {
        guard currentIndex > 0 else { return }
        if let shuffled = shuffledIndices {
            let keptRealIndices = Array(shuffled.dropFirst(currentIndex))
            let sortedKept = keptRealIndices.sorted()
            var oldToNew: [Int: Int] = [:]
            for (newIdx, oldIdx) in sortedKept.enumerated() {
                oldToNew[oldIdx] = newIdx
            }
            queue = sortedKept.map { queue[$0] }
            shuffledIndices = keptRealIndices.map { oldToNew[$0]! }
        } else {
            queue = Array(queue.dropFirst(currentIndex))
        }
        currentIndex = 0
        isQueueUserModified = true
        savePlaybackState()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let upNextStart = currentIndex + 1
        let realOffsets = IndexSet(offsets.map { upNextStart + $0 })
        let effectiveOffsets: [Int]
        if let shuffled = shuffledIndices {
            effectiveOffsets = realOffsets.compactMap { idx in
                idx < shuffled.count ? shuffled[idx] : nil
            }
        } else {
            effectiveOffsets = Array(realOffsets)
        }
        for idx in effectiveOffsets.sorted().reversed() {
            guard idx < queue.count else { continue }
            queue.remove(at: idx)
            if var shuffled = shuffledIndices {
                shuffled = shuffled.compactMap { i in
                    if i == idx { return nil }
                    return i > idx ? i - 1 : i
                }
                shuffledIndices = shuffled
            }
        }
        isQueueUserModified = true
        invalidateGaplessState()
        savePlaybackState()
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        let nextBefore = upcomingTrackId
        let upNextStart = currentIndex + 1
        if let shuffled = shuffledIndices {
            var upNextIndices = Array(shuffled[upNextStart...])
            upNextIndices.move(fromOffsets: source, toOffset: destination)
            shuffledIndices = Array(shuffled[..<upNextStart]) + upNextIndices
        } else {
            let sourceReal = IndexSet(source.map { $0 + upNextStart })
            let destReal = destination + upNextStart
            queue.move(fromOffsets: sourceReal, toOffset: destReal)
        }
        isQueueUserModified = true
        if upcomingTrackId != nextBefore { invalidateGaplessState() }
        savePlaybackState()
    }

    /// The track queued to play after the current one, which is all the gapless prefetch
    /// depends on.
    private var upcomingTrackId: UUID? {
        let next = currentIndex + 1
        guard next < queue.count else { return nil }
        let effective = shuffledIndices.map { next < $0.count ? $0[next] : next } ?? next
        return queue.indices.contains(effective) ? queue[effective].track.id : nil
    }

    // MARK: - Shuffle

    func toggleShuffle() {
        if shuffledIndices != nil {
            let realIndex = effectiveIndex
            shuffledIndices = nil
            currentIndex = realIndex
        } else {
            let realIndex = effectiveIndex
            var indices = SmartShuffle.shuffledIndices(for: queue, spread: settings.spreadShuffle)
            if let pos = indices.firstIndex(of: realIndex), pos != 0 {
                indices.swapAt(0, pos)
            }
            shuffledIndices = indices
            currentIndex = 0
        }
        settings.isShuffled = isShuffled
        invalidateGaplessState()
        savePlaybackState()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        settings.repeatMode = repeatMode
        invalidateGaplessState()
    }

    // MARK: - Playback Engine

    private func loadAndPlayCurrent() async {
        let idx = effectiveIndex
        guard idx >= 0 && idx < queue.count else { return }
        let track = queue[idx].track

        // Request background time so iOS doesn't suspend mid-transition
        #if os(iOS)
        let bgTask = UIApplication.shared.beginBackgroundTask()
        defer {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        #endif

        let resumeTime = pendingResume.flatMap { $0.trackId == track.id ? $0.time : nil } ?? 0
        pendingResume = nil

        isLoadingTrack = true
        isBuffering = true
        playbackError = nil
        isSeeking = false
        currentTrack = track
        progress = resumeTime
        duration = track.duration
        hasQueuedGaplessItem = false

        updateNowPlayingInfo()
        savePlaybackState()

        // Stop current playback — remove all items from AVQueuePlayer
        primaryPlayer.pause()
        primaryPlayer.removeAllItems()
        tearDownCrossfade()

        do {
            let playbackURL = try resolvePlaybackURL(for: track, queueIndex: idx)

            activateAudioSession()
            // Disable stalling wait for local files (better gapless), enable for remote streams
            primaryPlayer.automaticallyWaitsToMinimizeStalling = !playbackURL.isFileURL
            let item = makePlayerItem(url: playbackURL)
            currentPlayerItem = item
            gaplessPlayerItem = nil
            observeStatus(of: item)
            primaryPlayer.insert(item, after: nil)
            if resumeTime > 0 {
                await primaryPlayer.seek(to: CMTime(seconds: resumeTime, preferredTimescale: 600),
                                         toleranceBefore: .zero, toleranceAfter: .zero)
            }
            primaryGain = normalizationGain(for: track)
            primaryPlayer.volume = Float(volume) * primaryGain
            primaryPlayer.play()
            isLoadingTrack = false
            isPlaying = true
            // A local file is ready the moment it's inserted; only a stream can hang.
            if playbackURL.isFileURL {
                isBuffering = false
            } else {
                startStallWatchdog()
            }

            updateNowPlayingPlaybackState()
            await prefetchNextTrackAsync()
            setupGaplessOrCrossfade()
        } catch APIError.unauthorized {
            #if DEBUG
            print("PlayerService: playback failed — session expired")
            #endif
            failPlayback(String(localized: "Your session expired. Sign in again to keep listening."))
            NotificationCenter.default.post(name: .sessionExpired, object: nil)
        } catch {
            #if DEBUG
            print("PlayerService: failed to load track: \(error)")
            #endif
            // Stop instead of skip to avoid recursive failure loops when backgrounded
            failPlayback(error.localizedDescription)
        }
    }

    /// Watches the item we just handed the player. `.failed` is the only signal
    /// AVFoundation gives us for a stream it can't play — nothing is thrown.
    private func observeStatus(of item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, observed === self.currentPlayerItem else { return }
                switch observed.status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.playbackError = nil
                    self.stallWatchdog?.cancel()
                    self.stallWatchdog = nil
                case .failed:
                    self.failPlayback(observed.error?.localizedDescription
                        ?? String(localized: "This track couldn't be played."))
                default:
                    break
                }
            }
        }
    }

    /// A stream that is rejected or black-holed never reports an error and never times
    /// out on its own — without this the UI shows a pause button at 0:00 indefinitely.
    private func startStallWatchdog() {
        stallWatchdog?.cancel()
        stallWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.stallTimeout))
            guard !Task.isCancelled, let self else { return }
            guard let item = currentPlayerItem, item.status != .readyToPlay else { return }
            failPlayback(String(localized: "Couldn't reach the server to play this track."))
        }
    }

    private func failPlayback(_ message: String) {
        stallWatchdog?.cancel()
        stallWatchdog = nil
        isLoadingTrack = false
        isBuffering = false
        isPlaying = false
        primaryPlayer.pause()
        playbackError = message
        updateNowPlayingPlaybackState()
    }

    private func resolvePlaybackURL(for track: Track, queueIndex: Int) throws -> URL {
        // The index is resolved before this runs and the queue can be replaced in
        // between — a crash report caught exactly that, coming in via playShuffled.
        // Writing the resolved URL back only memoises it for the next play of the same
        // row, so a stale index means skip the memo, never trap.
        func rememberURL(_ url: URL) {
            guard queue.indices.contains(queueIndex) else { return }
            queue[queueIndex].playbackURL = url
        }

        if let offlineURL = musicLibrary?.localURL(for: track.id) {
            rememberURL(offlineURL)
            return offlineURL
        }
        if queue.indices.contains(queueIndex),
           let cached = queue[queueIndex].playbackURL,
           !cached.isFileURL || FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        if let cachedURL = playbackCache?.cachedURL(for: track.id) {
            rememberURL(cachedURL)
            return cachedURL
        }
        guard var streamURL = URL(string: track.streamUrl) else {
            throw URLError(.badURL)
        }
        // Determine streaming preset: user setting, or force transcode for unsupported formats
        let streamingQuality = settings.streamingQuality
        let needsTranscode = streamingQuality != .original || !AudioFormat.isAVPlayerSupported(track.mimetype)
        let preset = streamingQuality != .original ? streamingQuality.rawValue : "default_adts"
        if needsTranscode {
            if var comps = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) {
                var queryItems = comps.queryItems ?? []
                queryItems.append(URLQueryItem(name: "transcode", value: "1"))
                queryItems.append(URLQueryItem(name: "preset", value: preset))
                comps.queryItems = queryItems
                if let transcodedURL = comps.url {
                    streamURL = transcodedURL
                }
            }
        }
        if let cache = playbackCache {
            let cacheURL = streamURL
            Task.detached {
                let _ = await cache.cacheTrack(trackId: track.id, from: cacheURL, sessionToken: self.api.sessionToken)
            }
        }
        return streamURL
    }

    /// Creates an AVPlayerItem, attaching Bearer auth headers for remote URLs.
    private func makePlayerItem(url: URL) -> AVPlayerItem {
        if url.isFileURL {
            return AVPlayerItem(url: url)
        }
        let headers = ["Authorization": "Bearer \(api.sessionToken)"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        return AVPlayerItem(asset: asset)
    }

    private func prefetchNextTrackAsync() async {
        guard let next = nextTrackInfo() else { return }
        let nextEffective = next.effectiveIndex
        guard nextEffective < queue.count, queue[nextEffective].playbackURL == nil else { return }
        let track = queue[nextEffective].track
        do {
            let _ = try resolvePlaybackURL(for: track, queueIndex: nextEffective)
        } catch {}
    }

    // MARK: - Gapless / Crossfade

    private func nextTrackInfo() -> (index: Int, effectiveIndex: Int)? {
        guard !queue.isEmpty else { return nil }
        let nextIdx = currentIndex + 1
        let resolvedIdx: Int
        if nextIdx < queue.count {
            resolvedIdx = nextIdx
        } else if repeatMode == .all {
            resolvedIdx = 0
        } else {
            return nil
        }
        let eff: Int
        if let shuffled = shuffledIndices {
            guard resolvedIdx < shuffled.count else { return nil }
            eff = shuffled[resolvedIdx]
        } else {
            eff = resolvedIdx
        }
        guard eff < queue.count else { return nil }
        return (resolvedIdx, eff)
    }

    private func isNextTrackSequential() -> Bool {
        guard let next = nextTrackInfo() else { return false }
        let currentTrackItem = queue[effectiveIndex].track
        let nextTrack = queue[next.effectiveIndex].track
        guard currentTrackItem.albumId == nextTrack.albumId else { return false }

        if let currentNumber = currentTrackItem.number, let nextNumber = nextTrack.number,
           nextTrack.disc == currentTrackItem.disc && nextNumber == currentNumber + 1 {
            return true
        }
        if let nextNumber = nextTrack.number,
           nextTrack.disc == currentTrackItem.disc + 1 && nextNumber == 1 {
            return true
        }
        return false
    }

    /// Decides whether to use AVQueuePlayer gapless (sequential tracks) or crossfade (non-sequential).
    private func setupGaplessOrCrossfade() {
        guard repeatMode != .one else { return }

        if isNextTrackSequential() {
            enqueueNextForGapless()
        } else {
            setupCrossfadeObserverIfNeeded()
        }
    }

    /// Invalidates gapless/crossfade state when queue changes. Re-evaluates what to do.
    private func invalidateGaplessState() {
        // Remove any queued gapless item from AVQueuePlayer
        if hasQueuedGaplessItem {
            // AVQueuePlayer: remove all items after current
            while primaryPlayer.items().count > 1 {
                if let last = primaryPlayer.items().last {
                    primaryPlayer.remove(last)
                }
            }
            hasQueuedGaplessItem = false
            gaplessPlayerItem = nil
        }
        tearDownCrossfade()
        setupGaplessOrCrossfade()
    }

    /// Inserts the next track into AVQueuePlayer for native gapless playback.
    /// Assumes prefetch has already resolved the URL.
    private func enqueueNextForGapless() {
        guard !hasQueuedGaplessItem else { return }
        guard let next = nextTrackInfo() else { return }
        let nextEffective = next.effectiveIndex
        guard nextEffective < queue.count else { return }

        // URL should already be resolved by prefetch
        guard let url = queue[nextEffective].playbackURL else {
            // Fallback: resolve async if prefetch somehow missed it
            let nextTrack = queue[nextEffective].track
            Task {
                do {
                    let url = try resolvePlaybackURL(for: nextTrack, queueIndex: nextEffective)
                    let item = self.makePlayerItem(url: url)
                    if self.primaryPlayer.canInsert(item, after: self.primaryPlayer.items().last) {
                        self.primaryPlayer.insert(item, after: self.primaryPlayer.items().last)
                        self.gaplessPlayerItem = item
                        self.hasQueuedGaplessItem = true
                    }
                } catch {
                    #if DEBUG
                    print("PlayerService: failed to enqueue gapless item: \(error)")
                    #endif
                }
            }
            return
        }

        let item = makePlayerItem(url: url)
        if primaryPlayer.canInsert(item, after: primaryPlayer.items().last) {
            primaryPlayer.insert(item, after: primaryPlayer.items().last)
            gaplessPlayerItem = item
            hasQueuedGaplessItem = true
        }
    }

    // MARK: - Time Observer

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = primaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isSeeking, !self.isLoadingTrack else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                self.progress = seconds
            }
            if let item = self.primaryPlayer.currentItem {
                let dur = item.duration.seconds
                if dur.isFinite && dur > 0 {
                    self.duration = dur
                }
            }
            self.accumulateListening(to: seconds)
            self.savePositionIfDue()
        }
    }

    private var playThreshold: Double {
        let trackLength = currentTrack?.duration ?? 0
        return PlayThreshold.seconds(forDuration: trackLength > 0 ? trackLength : duration)
    }

    private func accumulateListening(to seconds: Double) {
        guard let track = currentTrack, seconds.isFinite else { return }
        defer { lastProgressSample = seconds }
        guard let previous = lastProgressSample else { return }

        // Only forward movement at about real time counts. A seek jumps, and a jump
        // backwards is a repeat rather than listening to count twice.
        let delta = seconds - previous
        guard delta > 0, delta < 2 else { return }
        listenedSeconds += delta

        guard !hasReportedCurrentPlay, listenedSeconds >= playThreshold else { return }
        hasReportedCurrentPlay = true
        // Checked at the moment it qualifies rather than when it started, so turning the
        // setting off mid-track stops that track being counted.
        guard settings.recordPlays else { return }
        let playedAt = playStartedAt ?? Date()
        musicLibrary?.recordLocalPlay(trackId: track.id, at: playedAt)
        outbox?.enqueuePlay(trackId: track.id, playedAt: playedAt)
    }

    // MARK: - End Observer

    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let item = notification.object as? AVPlayerItem else { return }

            // Only handle notifications for items we're tracking
            if item === self.currentPlayerItem {
                if self.hasQueuedGaplessItem {
                    self.advanceAfterGapless()
                } else {
                    self.skip()
                }
            }
            // Ignore notifications from stale/unknown items
        }
    }

    /// Called when AVQueuePlayer auto-advances to the queued gapless item.
    private func advanceAfterGapless() {
        hasQueuedGaplessItem = false
        // The gapless item is now the active item
        currentPlayerItem = gaplessPlayerItem
        gaplessPlayerItem = nil

        guard let next = nextTrackInfo() else {
            skip()
            return
        }

        currentIndex = next.index
        let nextTrack = queue[next.effectiveIndex].track
        currentTrack = nextTrack
        progress = 0
        duration = nextTrack.duration
        isPlaying = true
        // Both tracks share one AVQueuePlayer here, so the gain has to change under the
        // playhead at the boundary rather than travelling with a second player.
        primaryGain = normalizationGain(for: nextTrack)
        applyVolume()

        updateNowPlayingInfo()
        savePlaybackState()
        Task {
            await prefetchNextTrackAsync()
            setupGaplessOrCrossfade()
        }
    }

    // MARK: - Crossfade

    private func setupCrossfadeObserverIfNeeded() {
        let fadeDuration = settings.crossfadeDuration
        guard fadeDuration > 0, repeatMode != .one else { return }

        // Verify there's a next track
        guard nextTrackInfo() != nil else { return }

        if let crossfadeObserver { primaryPlayer.removeTimeObserver(crossfadeObserver) }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        crossfadeObserver = primaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            guard let item = self.primaryPlayer.currentItem else { return }

            let dur = item.duration.seconds
            let current = time.seconds

            guard dur.isFinite && current.isFinite else { return }
            let remaining = dur - current
            if remaining <= fadeDuration && remaining > 0 {
                self.beginCrossfade(fadeDuration: fadeDuration, remaining: remaining)
            }
        }
    }

    private func beginCrossfade(fadeDuration: Double, remaining: Double) {
        guard secondaryPlayer == nil else { return }

        guard let next = nextTrackInfo() else { return }
        let nextIdx = next.index
        let nextEffective = next.effectiveIndex

        // Remove observers — crossfade handles the transition
        if let crossfadeObserver {
            primaryPlayer.removeTimeObserver(crossfadeObserver)
            self.crossfadeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let nextTrack = queue[nextEffective].track

        Task {
            do {
                let playbackURL = try resolvePlaybackURL(for: nextTrack, queueIndex: nextEffective)
                await MainActor.run {
                    let item = self.makePlayerItem(url: playbackURL)
                    let crossfadePlayer = AVQueuePlayer(items: [item])
                    self.secondaryPlayer = crossfadePlayer
                    self.secondaryGain = self.normalizationGain(for: nextTrack)
                    crossfadePlayer.volume = 0
                    crossfadePlayer.play()
                    self.startVolumeRamp(fadeDuration: min(fadeDuration, remaining), nextIndex: nextIdx, nextTrack: nextTrack)
                }
            } catch {
                #if DEBUG
                print("PlayerService: crossfade failed: \(error)")
                #endif
                await MainActor.run { self.tearDownCrossfade() }
            }
        }
    }

    private func startVolumeRamp(fadeDuration: Double, nextIndex: Int, nextTrack: Track) {
        let startTime = Date()
        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, let secondary = self.secondaryPlayer else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(Float(elapsed / fadeDuration), 1.0)
            self.primaryPlayer.volume = Float(self.volume) * self.primaryGain * cos(progress * .pi * 0.5)
            secondary.volume = Float(self.volume) * self.secondaryGain * sin(progress * .pi * 0.5)

            if progress >= 1.0 {
                timer.invalidate()
                self.completeCrossfade(nextIndex: nextIndex, nextTrack: nextTrack)
            }
        }
    }

    private func completeCrossfade(nextIndex: Int, nextTrack: Track) {
        if let timeObserver { primaryPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let crossfadeObserver { primaryPlayer.removeTimeObserver(crossfadeObserver) }
        crossfadeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil

        primaryPlayer.pause()
        primaryPlayer.removeAllItems()

        currentIndex = nextIndex
        currentTrack = nextTrack
        hasQueuedGaplessItem = false
        progress = 0
        duration = nextTrack.duration
        isPlaying = true
        isLoadingTrack = true  // Prevent time observer from updating progress during seek

        if let secondary = secondaryPlayer {
            // Promote secondary directly — it's already an AVQueuePlayer playing at the correct position.
            // No pause/recreate/seek needed, which avoids stutter/rewind artifacts.
            primaryGain = secondaryGain
            secondary.volume = Float(volume) * primaryGain
            primaryPlayer = secondary
            currentPlayerItem = secondary.currentItem
            gaplessPlayerItem = nil
            secondaryPlayer = nil
            isLoadingTrack = false
        } else {
            isLoadingTrack = false
        }

        setupTimeObserver()
        setupEndObserver()
        updateNowPlayingInfo()
        savePlaybackState()
        Task {
            await prefetchNextTrackAsync()
            setupGaplessOrCrossfade()
        }
    }

    private func tearDownCrossfade() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        if let crossfadeObserver {
            primaryPlayer.removeTimeObserver(crossfadeObserver)
            self.crossfadeObserver = nil
        }
        secondaryPlayer?.pause()
        secondaryPlayer?.replaceCurrentItem(with: nil)
        secondaryPlayer = nil
        secondaryGain = 1
        if endObserver == nil {
            setupEndObserver()
        }
    }

    // MARK: - State Persistence

    /// Minimum gap between position writes driven by the periodic time observer.
    private static let positionSaveInterval: TimeInterval = 5

    /// Writes the queue so a relaunch can pick playback back up. iOS suspends a paused app
    /// and may terminate it minutes later, and nothing about the queue lives anywhere but
    /// memory otherwise. Call whenever the queue or the current index changes.
    func savePlaybackState() {
        guard !queue.isEmpty else { return }
        stateStore.save(PlaybackState(
            trackIds: queue.map(\.track.id),
            currentIndex: currentIndex,
            shuffledIndices: shuffledIndices,
            isUserModified: isQueueUserModified
        ))
        savePlaybackPosition()
    }

    /// Writes just how far into the current track playback has got — the half that changes
    /// continuously, kept out of the queue file so it isn't rewritten every few seconds.
    func savePlaybackPosition() {
        guard let track = currentTrack else { return }
        lastPositionSave = .now
        stateStore.savePosition(PlaybackPosition(trackId: track.id, elapsed: progress))
    }

    private func savePositionIfDue() {
        guard Date.now.timeIntervalSince(lastPositionSave) >= Self.positionSaveInterval else { return }
        savePlaybackPosition()
    }

    private func restoreState() {
        guard let musicLibrary, let state = stateStore.load(), !state.trackIds.isEmpty else { return }

        let byId = musicLibrary.tracks(ids: state.trackIds)
        let tracks = state.trackIds.compactMap { byId[$0] }
        // A partial restore would shift every index, including the shuffle order. The
        // snapshot is a convenience, so drop it rather than reconstruct a different queue.
        guard tracks.count == state.trackIds.count else { return }

        queue = tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
        if let shuffled = state.shuffledIndices, shuffled.count == queue.count {
            shuffledIndices = shuffled
        }
        currentIndex = min(max(state.currentIndex, 0), queue.count - 1)
        // A hand-built queue keeps its protection across a restart.
        isQueueUserModified = state.isUserModified ?? false

        let idx = effectiveIndex
        guard idx < queue.count else {
            queue = []
            shuffledIndices = nil
            currentIndex = 0
            return
        }
        let track = queue[idx].track
        currentTrack = track
        duration = track.duration

        // The position is written separately and may lag the queue by a few seconds; ignore
        // it unless it belongs to the track the queue says is current.
        guard let position = stateStore.loadPosition(), position.trackId == track.id else { return }
        progress = position.elapsed
        pendingResume = (track.id, position.elapsed)
    }

    // MARK: - Audio Session (iOS)

    private func activateAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            #if DEBUG
            print("PlayerService: audio session activation failed: \(error)")
            #endif
        }
        #endif
    }

    private func setupAudioSession() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            switch type {
            case .began:
                self.isPlaying = false
                self.updateNowPlayingPlaybackState()
            case .ended:
                if let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.primaryPlayer.play()
                        self.isPlaying = true
                        self.updateNowPlayingPlaybackState()
                    }
                }
            @unknown default:
                break
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
            if reason == .oldDeviceUnavailable {
                self.primaryPlayer.pause()
                self.isPlaying = false
                self.updateNowPlayingPlaybackState()
            }
        }
        #endif
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artist.name,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let number = track.number {
            info[MPMediaItemPropertyAlbumTrackNumber] = number
        }
        let idx = effectiveIndex
        let artworkURL = (idx >= 0 && idx < queue.count) ? queue[idx].artworkURL : nil

        if let artworkURL, artworkURL == nowPlayingArtworkURL, let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let artworkURL,
                  let cached = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: artworkURL)) {
            let artwork = MPMediaItemArtwork(boundsSize: cached.image.size) { _ in cached.image }
            nowPlayingArtwork = artwork
            nowPlayingArtworkURL = artworkURL
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateRemoteCommandStates()

        guard let artworkURL, artworkURL != nowPlayingArtworkURL else { return }
        let trackId = track.id
        Task {
            do {
                let image = try await ImagePipeline.shared.image(for: artworkURL)
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    guard self.currentTrack?.id == trackId else { return }
                    self.nowPlayingArtwork = artwork
                    self.nowPlayingArtworkURL = artworkURL
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
                }
            } catch {}
        }
    }

    private func updateNowPlayingElapsed() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
    }

    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateRemoteCommandStates()
    }

    private func updateRemoteCommandStates() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = canSkip
        center.previousTrackCommand.isEnabled = canGoBack
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // The play/pause media key reaches the Now Playing app as this command, and with
        // no handler for it the system falls back to guessing play or pause from
        // `MPNowPlayingInfoCenter.playbackState`. That guess is what made the key feel
        // unreliable — it has to match our state exactly, and it's stale for a moment
        // after every track change.
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            self?.resumePlayback()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pausePlayback()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skip()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.back()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: posEvent.positionTime)
            return .success
        }
        center.changeShuffleModeCommand.addTarget { [weak self] _ in
            self?.toggleShuffle()
            return .success
        }
        center.changeRepeatModeCommand.addTarget { [weak self] _ in
            self?.cycleRepeatMode()
            return .success
        }
    }
}
