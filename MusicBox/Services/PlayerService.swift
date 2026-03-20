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

    var queue: [QueueItem] = []
    var currentIndex: Int = 0
    var shuffledIndices: [Int]? = nil
    var repeatMode: RepeatMode = .off
    var isPlaying: Bool = false
    var currentTrack: Track? = nil
    var progress: Double = 0
    var duration: Double = 0
    var queueConfirmation: QueueConfirmation? = nil
    var showReplaceQueueConfirmation: Bool = false
    @ObservationIgnored private var pendingPlayAction: (() -> Void)?

    nonisolated enum QueueConfirmation: Equatable, Sendable {
        case playNext(Int)
        case addedToQueue(Int)
    }

    func requestPlay(_ action: @escaping () -> Void) {
        if currentTrack != nil && queueHasMultipleAlbums {
            pendingPlayAction = action
            showReplaceQueueConfirmation = true
        } else {
            action()
        }
    }

    private var queueHasMultipleAlbums: Bool {
        guard let firstAlbumId = queue.first?.track.albumId else { return false }
        return queue.contains { $0.track.albumId != firstAlbumId }
    }

    func confirmPlay() {
        pendingPlayAction?()
        pendingPlayAction = nil
    }

    func cancelPlay() {
        pendingPlayAction = nil
    }

    var isShuffled: Bool { shuffledIndices != nil }

    // MARK: - Private

    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let tokenManager = PlayTokenManager()
    @ObservationIgnored private let musicLibrary: MusicLibrary?
    @ObservationIgnored private let playbackCache: PlaybackCache?
    @ObservationIgnored private var primaryPlayer = AVQueuePlayer()
    @ObservationIgnored private var secondaryPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var crossfadeObserver: Any?
    @ObservationIgnored private var crossfadeTimer: Timer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var nowPlayingArtworkURL: URL?
    @ObservationIgnored private var isSeeking: Bool = false
    @ObservationIgnored private var isLoadingTrack: Bool = false
    /// Tracks whether AVQueuePlayer has a queued next item for gapless playback
    @ObservationIgnored private var hasQueuedGaplessItem: Bool = false

    // MARK: - Computed

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

    init(api: APIService, settings: SettingsStore, musicLibrary: MusicLibrary? = nil, playbackCache: PlaybackCache? = nil) {
        self.api = api
        self.settings = settings
        self.musicLibrary = musicLibrary
        self.playbackCache = playbackCache
        self.repeatMode = settings.repeatMode
        setupTimeObserver()
        setupEndObserver()
        setupAudioSession()
        setupRemoteCommands()
    }

    deinit {
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
        Task { await loadAndPlayCurrent() }
    }

    func playNow(queue items: [QueueItem], startingAt index: Int = 0) {
        queue = items
        shuffledIndices = nil
        currentIndex = index
        Task { await loadAndPlayCurrent() }
    }

    func playShuffled(tracks: [Track], artworkURL: URL? = nil) {
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL ?? $0.album?.artworkUrl) }
        playShuffled(queue: items)
    }

    func playShuffled(queue items: [QueueItem]) {
        guard !items.isEmpty else { return }
        queue = items
        var indices = Array(items.indices)
        indices.shuffle()
        shuffledIndices = indices
        currentIndex = 0
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
        if let shuffled = shuffledIndices {
            let newIndices = items.indices.map { insertIndex + $0 }
            shuffledIndices = shuffled.map { $0 >= insertIndex ? $0 + items.count : $0 } + newIndices
        }
        queueConfirmation = .playNext(items.count)
        invalidateGaplessState()
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
        if shuffledIndices != nil {
            let newIndices = items.indices.map { startIndex + $0 }
            shuffledIndices! += newIndices
        }
        queueConfirmation = .addedToQueue(items.count)
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
            currentIndex = 0
            let idx = effectiveIndex
            if idx < queue.count {
                currentTrack = queue[idx].track
                duration = queue[idx].track.duration
            }
            progress = 0
            updateNowPlayingInfo()
            updateNowPlayingPlaybackState()
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
        } else if primaryPlayer.currentItem == nil && !queue.isEmpty {
            Task { await loadAndPlayCurrent() }
            return
        } else {
            primaryPlayer.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
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
        invalidateGaplessState()
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
            if shuffledIndices != nil {
                shuffledIndices = shuffledIndices!.compactMap { i in
                    if i == idx { return nil }
                    return i > idx ? i - 1 : i
                }
            }
        }
        invalidateGaplessState()
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
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
        invalidateGaplessState()
    }

    // MARK: - Shuffle

    func toggleShuffle() {
        if shuffledIndices != nil {
            let realIndex = effectiveIndex
            shuffledIndices = nil
            currentIndex = realIndex
        } else {
            let realIndex = effectiveIndex
            var indices = Array(queue.indices)
            indices.removeAll { $0 == realIndex }
            indices.shuffle()
            indices.insert(realIndex, at: 0)
            shuffledIndices = indices
            currentIndex = 0
        }
        settings.isShuffled = isShuffled
        invalidateGaplessState()
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

        isLoadingTrack = true
        isSeeking = false
        currentTrack = track
        progress = 0
        duration = track.duration
        hasQueuedGaplessItem = false

        updateNowPlayingInfo()

        // Stop current playback — remove all items from AVQueuePlayer
        primaryPlayer.pause()
        primaryPlayer.removeAllItems()
        tearDownCrossfade()

        do {
            let playbackURL = try await resolvePlaybackURL(for: track, queueIndex: idx)

            activateAudioSession()
            // Disable stalling wait for local files (better gapless), enable for remote streams
            primaryPlayer.automaticallyWaitsToMinimizeStalling = !playbackURL.isFileURL
            let item = AVPlayerItem(url: playbackURL)
            primaryPlayer.insert(item, after: nil)
            primaryPlayer.volume = 1.0
            primaryPlayer.play()
            isLoadingTrack = false
            isPlaying = true

            updateNowPlayingPlaybackState()
            await prefetchNextTrackAsync()
            setupGaplessOrCrossfade()
        } catch {
            isLoadingTrack = false
            print("PlayerService: failed to load track: \(error)")
            // Stop instead of skip to avoid recursive failure loops when backgrounded
            isPlaying = false
            primaryPlayer.pause()
            updateNowPlayingPlaybackState()
        }
    }

    private func resolvePlaybackURL(for track: Track, queueIndex: Int) async throws -> URL {
        if let offlineURL = musicLibrary?.localURL(for: track.id) {
            queue[queueIndex].playbackURL = offlineURL
            return offlineURL
        }
        if let cached = queue[queueIndex].playbackURL,
           !cached.isFileURL || FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        if let cachedURL = playbackCache?.cachedURL(for: track.id) {
            queue[queueIndex].playbackURL = cachedURL
            return cachedURL
        }
        var streamURL = try await tokenManager.resolvedStreamURL(for: track, using: api)
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
            Task.detached {
                let _ = await cache.cacheTrack(trackId: track.id, from: streamURL)
            }
        }
        return streamURL
    }

    private func prefetchNextTrackAsync() async {
        guard let next = nextTrackInfo() else { return }
        let nextEffective = next.effectiveIndex
        guard nextEffective < queue.count, queue[nextEffective].playbackURL == nil else { return }
        let track = queue[nextEffective].track
        do {
            let _ = try await resolvePlaybackURL(for: track, queueIndex: nextEffective)
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

        if nextTrack.disc == currentTrackItem.disc && nextTrack.number == currentTrackItem.number + 1 {
            return true
        }
        if nextTrack.disc == currentTrackItem.disc + 1 && nextTrack.number == 1 {
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
                    let url = try await resolvePlaybackURL(for: nextTrack, queueIndex: nextEffective)
                    let item = AVPlayerItem(url: url)
                    if self.primaryPlayer.canInsert(item, after: self.primaryPlayer.items().last) {
                        self.primaryPlayer.insert(item, after: self.primaryPlayer.items().last)
                        self.hasQueuedGaplessItem = true
                    }
                } catch {
                    print("PlayerService: failed to enqueue gapless item: \(error)")
                }
            }
            return
        }

        let item = AVPlayerItem(url: url)
        if primaryPlayer.canInsert(item, after: primaryPlayer.items().last) {
            primaryPlayer.insert(item, after: primaryPlayer.items().last)
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
        }
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

            // If gapless: AVQueuePlayer auto-advances. We just need to update our state.
            if self.hasQueuedGaplessItem, item === self.primaryPlayer.items().first || self.primaryPlayer.items().count <= 1 {
                self.advanceAfterGapless()
                return
            }

            // Non-gapless: only handle primary player's current item
            if item === self.primaryPlayer.currentItem {
                self.skip()
            }
        }
    }

    /// Called when AVQueuePlayer auto-advances to the queued gapless item.
    private func advanceAfterGapless() {
        hasQueuedGaplessItem = false

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

        updateNowPlayingInfo()
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
                let playbackURL = try await resolvePlaybackURL(for: nextTrack, queueIndex: nextEffective)
                await MainActor.run {
                    let item = AVPlayerItem(url: playbackURL)
                    let crossfadePlayer = AVPlayer(playerItem: item)
                    self.secondaryPlayer = crossfadePlayer
                    crossfadePlayer.volume = 0
                    crossfadePlayer.play()
                    self.startVolumeRamp(fadeDuration: min(fadeDuration, remaining), nextIndex: nextIdx, nextTrack: nextTrack)
                }
            } catch {
                print("PlayerService: crossfade failed: \(error)")
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
            self.primaryPlayer.volume = cos(progress * .pi * 0.5)
            secondary.volume = sin(progress * .pi * 0.5)

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

        if let secondary = secondaryPlayer {
            // Create new AVQueuePlayer from the secondary player's item
            if let item = secondary.currentItem {
                let newPlayer = AVQueuePlayer(items: [item])
                let isLocal = item.asset is AVURLAsset && (item.asset as? AVURLAsset)?.url.isFileURL == true
                newPlayer.automaticallyWaitsToMinimizeStalling = !isLocal
                newPlayer.volume = secondary.volume
                // Seek to match secondary's current position
                let currentTime = secondary.currentTime()
                secondary.pause()
                newPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                newPlayer.play()
                primaryPlayer = newPlayer
            }
            secondaryPlayer = nil
        }

        currentIndex = nextIndex
        currentTrack = nextTrack
        hasQueuedGaplessItem = false
        progress = 0
        duration = nextTrack.duration
        isPlaying = true

        setupTimeObserver()
        setupEndObserver()
        updateNowPlayingInfo()
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
        if endObserver == nil {
            setupEndObserver()
        }
    }

    // MARK: - Audio Session (iOS)

    private func activateAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("PlayerService: audio session activation failed: \(error)")
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
        info[MPMediaItemPropertyAlbumTrackNumber] = track.number
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
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
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
