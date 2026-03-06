import AVFoundation
import MediaPlayer
import SwiftUI

nonisolated enum RepeatMode: Sendable {
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

    var isShuffled: Bool { shuffledIndices != nil }

    // MARK: - Private

    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let tokenManager = PlayTokenManager()
    @ObservationIgnored private let offlineStore: OfflineStore?
    @ObservationIgnored private var primaryPlayer = AVPlayer()
    @ObservationIgnored private var secondaryPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var crossfadeObserver: Any?
    @ObservationIgnored private var crossfadeTimer: Timer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var routeChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?

    // MARK: - Computed

    var effectiveIndex: Int {
        if let shuffled = shuffledIndices {
            guard currentIndex >= 0 && currentIndex < shuffled.count else { return 0 }
            return shuffled[currentIndex]
        }
        return currentIndex
    }

    // MARK: - Init

    init(api: APIService, settings: SettingsStore, offlineStore: OfflineStore? = nil) {
        self.api = api
        self.settings = settings
        self.offlineStore = offlineStore
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
        queue = tracks.map { QueueItem(track: $0, artworkURL: artworkURL) }
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
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL) }
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
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL) }
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
    }

    func addToEnd(tracks: [Track], artworkURL: URL? = nil) {
        let items = tracks.map { QueueItem(track: $0, artworkURL: artworkURL) }
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
            // End of queue, repeat off
            isPlaying = false
            primaryPlayer.pause()
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
        } else {
            primaryPlayer.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackState()
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        primaryPlayer.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        progress = time
        updateNowPlayingElapsed()
    }

    func removeFromQueue(at offsets: IndexSet) {
        // Convert offsets from "up next" offsets (relative to currentIndex+1) to real queue indices
        let upNextStart = currentIndex + 1
        let realOffsets = IndexSet(offsets.map { upNextStart + $0 })

        // Map through shuffled indices if needed
        let effectiveOffsets: [Int]
        if let shuffled = shuffledIndices {
            effectiveOffsets = realOffsets.compactMap { idx in
                idx < shuffled.count ? shuffled[idx] : nil
            }
        } else {
            effectiveOffsets = Array(realOffsets)
        }

        // Remove from queue in reverse order to preserve indices
        for idx in effectiveOffsets.sorted().reversed() {
            guard idx < queue.count else { continue }
            queue.remove(at: idx)
            // Adjust shuffled indices
            if shuffledIndices != nil {
                shuffledIndices = shuffledIndices!.compactMap { i in
                    if i == idx { return nil }
                    return i > idx ? i - 1 : i
                }
            }
        }
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        // These offsets are relative to the "up next" list
        let upNextStart = currentIndex + 1

        if let shuffled = shuffledIndices {
            // Move within the shuffled indices array (after currentIndex)
            var upNextIndices = Array(shuffled[upNextStart...])
            upNextIndices.move(fromOffsets: source, toOffset: destination)
            shuffledIndices = Array(shuffled[..<upNextStart]) + upNextIndices
        } else {
            // Move within the actual queue (after currentIndex)
            let sourceReal = IndexSet(source.map { $0 + upNextStart })
            let destReal = destination + upNextStart
            queue.move(fromOffsets: sourceReal, toOffset: destReal)
        }
    }

    // MARK: - Shuffle

    func toggleShuffle() {
        if shuffledIndices != nil {
            // Turn off: snap currentIndex to current track in original order
            let realIndex = effectiveIndex
            shuffledIndices = nil
            currentIndex = realIndex
        } else {
            // Turn on: generate permutation with current track first
            let realIndex = effectiveIndex
            var indices = Array(queue.indices)
            indices.removeAll { $0 == realIndex }
            indices.shuffle()
            indices.insert(realIndex, at: 0)
            shuffledIndices = indices
            currentIndex = 0
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Playback Engine

    private func loadAndPlayCurrent() async {
        let idx = effectiveIndex
        guard idx >= 0 && idx < queue.count else { return }
        let track = queue[idx].track

        currentTrack = track
        progress = 0
        duration = track.duration
        nowPlayingArtwork = nil

        // Stop current playback
        primaryPlayer.pause()
        tearDownCrossfade()

        do {
            let playbackURL: URL
            if let cached = queue[idx].playbackURL {
                playbackURL = cached
            } else if let offlineURL = offlineStore?.localURL(for: track.id) {
                playbackURL = offlineURL
                queue[idx].playbackURL = offlineURL
            } else {
                let url = try await tokenManager.resolvedStreamURL(for: track, using: api)
                playbackURL = url
                queue[idx].playbackURL = url
            }

            let item = AVPlayerItem(url: playbackURL)
            primaryPlayer.replaceCurrentItem(with: item)
            primaryPlayer.volume = 1.0
            primaryPlayer.play()
            isPlaying = true

            updateNowPlayingInfo()
            setupCrossfadeObserverIfNeeded()
            prefetchNextTrack()
        } catch {
            print("PlayerService: failed to load track: \(error)")
        }
    }

    private func prefetchNextTrack() {
        let nextIdx: Int
        let next = currentIndex + 1
        if next < queue.count {
            nextIdx = next
        } else if repeatMode == .all && !queue.isEmpty {
            nextIdx = 0
        } else {
            return
        }
        let nextEffective: Int
        if let shuffled = shuffledIndices, nextIdx < shuffled.count {
            nextEffective = shuffled[nextIdx]
        } else {
            nextEffective = nextIdx
        }
        guard nextEffective < queue.count, queue[nextEffective].playbackURL == nil else { return }
        let track = queue[nextEffective].track
        // Check offline store first
        if let offlineURL = offlineStore?.localURL(for: track.id) {
            queue[nextEffective].playbackURL = offlineURL
            return
        }
        Task {
            do {
                let url = try await tokenManager.resolvedStreamURL(for: track, using: api)
                await MainActor.run {
                    guard nextEffective < self.queue.count else { return }
                    self.queue[nextEffective].playbackURL = url
                }
            } catch {}
        }
    }

    // MARK: - Time Observer

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = primaryPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
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
            // Only handle if this is the primary player's item
            if let item = notification.object as? AVPlayerItem,
               item === self.primaryPlayer.currentItem {
                self.skip()
            }
        }
    }

    // MARK: - Crossfade

    private func setupCrossfadeObserverIfNeeded() {
        let fadeDuration = settings.crossfadeDuration
        guard fadeDuration > 0, repeatMode != .one else { return }

        // Check there's a next track
        let nextIdx = currentIndex + 1
        guard nextIdx < queue.count || repeatMode == .all else { return }

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
        // Only begin once
        guard secondaryPlayer == nil else { return }

        // Remove the end observer temporarily - crossfade handles transition
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        // Determine next track
        let nextIdx: Int
        let nextCurrent = currentIndex + 1
        if nextCurrent < queue.count {
            nextIdx = nextCurrent
        } else if repeatMode == .all {
            nextIdx = 0
        } else {
            return
        }

        let nextEffective: Int
        if let shuffled = shuffledIndices {
            guard nextIdx < shuffled.count else { return }
            nextEffective = shuffled[nextIdx]
        } else {
            nextEffective = nextIdx
        }
        guard nextEffective < queue.count else { return }

        let nextTrack = queue[nextEffective].track

        Task {
            do {
                let playbackURL: URL
                if let cached = queue[nextEffective].playbackURL {
                    playbackURL = cached
                } else if let offlineURL = offlineStore?.localURL(for: nextTrack.id) {
                    playbackURL = offlineURL
                    await MainActor.run { self.queue[nextEffective].playbackURL = offlineURL }
                } else {
                    let url = try await tokenManager.resolvedStreamURL(for: nextTrack, using: api)
                    playbackURL = url
                    await MainActor.run { self.queue[nextEffective].playbackURL = url }
                }
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
            let fraction = min(Float(elapsed / fadeDuration), 1.0)
            self.primaryPlayer.volume = 1.0 - fraction
            secondary.volume = fraction

            if fraction >= 1.0 {
                timer.invalidate()
                self.completeCrossfade(nextIndex: nextIndex, nextTrack: nextTrack)
            }
        }
    }

    private func completeCrossfade(nextIndex: Int, nextTrack: Track) {
        // Clean up old primary — remove its observers first
        if let timeObserver { primaryPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let crossfadeObserver { primaryPlayer.removeTimeObserver(crossfadeObserver) }
        crossfadeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil

        primaryPlayer.pause()
        primaryPlayer.replaceCurrentItem(with: nil)

        if let secondary = secondaryPlayer {
            primaryPlayer = secondary
            secondaryPlayer = nil
        }

        currentIndex = nextIndex
        currentTrack = nextTrack
        progress = 0
        duration = nextTrack.duration
        isPlaying = true

        // Re-attach observers to the new primary player
        setupTimeObserver()
        setupEndObserver()
        updateNowPlayingInfo()
        setupCrossfadeObserverIfNeeded()
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
        // Re-setup end observer if it was removed
        if endObserver == nil {
            setupEndObserver()
        }
    }

    // MARK: - Audio Session (iOS)

    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("PlayerService: audio session setup failed: \(error)")
        }

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
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Load artwork in background
        let idx = effectiveIndex
        guard idx >= 0 && idx < queue.count, let artworkURL = queue[idx].artworkURL else { return }
        let trackId = track.id
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                #if os(macOS)
                guard let image = NSImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                #else
                guard let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                #endif
                await MainActor.run {
                    // Only set if we're still on the same track
                    guard self.currentTrack?.id == trackId else { return }
                    self.nowPlayingArtwork = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
                }
            } catch {}
        }
    }

    private func updateNowPlayingElapsed() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
    }

    private func updateNowPlayingPlaybackState() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
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

