import Foundation

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Observable
final class DownloadService: NSObject, URLSessionDownloadDelegate {
    // MARK: - Public state

    /// Active downloads (in-flight): track ID → metadata
    var activeDownloads: [UUID: DownloadState] = [:]

    /// Ordered list of active download track IDs (for stable UI ordering)
    var activeDownloadOrder: [UUID] = []

    /// Downloads waiting to start
    var pendingQueue: [DownloadInfo] = []

    /// Whether all downloads are paused
    var isPaused: Bool = false

    /// Progress snapshot updated on a timer (~2x/sec) for UI display only
    var progressSnapshot: [UUID: Double] = [:]

    /// Downloads that failed (for user to retry or dismiss)
    var failedDownloads: [FailedDownload] = []

    /// Reason downloads are blocked by system conditions (nil when not blocked)
    var downloadsPausedReason: DownloadPausedReason?

    /// Set when the user chooses to download anyway despite Low Power Mode. Deliberately
    /// not persisted — it lasts the session, so the next launch defers to the system
    /// setting again rather than quietly ignoring it forever.
    ///
    /// Only Low Power Mode can be overridden. Low disk space is a real limit, not a
    /// preference, and filling the volume is a worse outcome than a stalled queue.
    var ignoresLowPowerMode = false {
        didSet {
            guard ignoresLowPowerMode, ignoresLowPowerMode != oldValue else { return }
            startNextIfNeeded()
        }
    }

    nonisolated enum DownloadPausedReason: Equatable {
        case lowPowerMode
        case lowDiskSpace
    }

    nonisolated struct FailedDownload: Identifiable, Sendable {
        let id: UUID  // track ID
        let trackName: String
        let artistName: String
        let info: DownloadInfo
        let reason: String
    }

    nonisolated struct DownloadState: Sendable {
        let trackName: String
        let artistName: String
        let albumId: UUID
        var isPaused: Bool = false
    }

    nonisolated struct DownloadInfo: Sendable {
        let track: Track
        let album: Album
        let artist: Artist
        var retryCount: Int = 0
    }

    /// Metadata stored in URLSessionTask.taskDescription — survives app termination.
    nonisolated struct TaskMetadata: Codable, Sendable {
        let trackId: UUID
        let artistId: UUID
        let albumId: UUID
        let mimetype: String
        let trackName: String
    }

    /// Written to disk when a download completes in background, processed on foreground.
    nonisolated struct PendingCompletion: Codable, Sendable {
        let trackId: UUID
        let relativePath: String
        var downloadedFileSize: Int64 = 0
    }

    // MARK: - Per-track download phase (consolidated state)

    /// Represents the lifecycle phase of a single download.
    private enum TrackPhase {
        /// URLSession download task in progress
        case downloading(task: URLSessionDownloadTask, taskId: Int, info: DownloadInfo)
        /// Download paused by user
        case paused(info: DownloadInfo)

        var info: DownloadInfo {
            switch self {
            case .downloading(_, _, let info), .paused(let info): info
            }
        }

        var isInFlight: Bool {
            switch self {
            case .downloading: true
            case .paused: false
            }
        }
    }

    // MARK: - Private

    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let settings: SettingsStore
    /// Current auth — nil when logged out. Updated via `configure(baseURL:sessionToken:)`.
    @ObservationIgnored private var baseURL: URL?
    @ObservationIgnored private var sessionToken: String?

    @ObservationIgnored private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.ondumusic.downloads.delegate"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    /// Per app rather than global, but derived from the bundle identifier so Debug and
    /// release never answer for each other's transfers.
    nonisolated static let backgroundSessionIdentifier = "\(Bundle.main.bundleIdentifier ?? "Ondu").downloads"

    /// Background session — survives app suspension/termination.
    /// Auth header is attached per-request (not via config) so we can swap tokens without recreating the session.
    @ObservationIgnored private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsConstrainedNetworkAccess = false
        config.timeoutIntervalForRequest = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    /// Foreground session — faster (no IPC overhead), used while app is active
    @ObservationIgnored private lazy var foregroundSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsConstrainedNetworkAccess = false
        config.timeoutIntervalForRequest = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    private var authorizedRequest: (URL) -> URLRequest? {
        { [weak self] url in
            guard let self, let token = self.sessionToken else { return nil }
            var req = URLRequest(url: url)
            // Only to the server signed in to; see APIService.mayReceiveToken.
            if let baseURL = self.baseURL, APIService.isSameOrigin(url, as: baseURL) {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            req.timeoutInterval = 300
            return req
        }
    }
    /// Whether the app is currently in the foreground
    @ObservationIgnored private var isInForeground: Bool = true

    /// Per-track download phase — single source of truth for all active/paused downloads
    @ObservationIgnored private var trackPhases: [UUID: TrackPhase] = [:]
    /// Reverse lookup: URLSession task identifier → track ID (for delegate callbacks)
    @ObservationIgnored private var taskIdToTrackId: [Int: UUID] = [:]
    /// Raw progress values keyed by track ID — used for cleanup tracking on main thread
    @ObservationIgnored private var progressValues: [UUID: Double] = [:]
    /// Progress values keyed by task ID — written from delegate queue (lock-protected), read by timer
    @ObservationIgnored private var taskProgressValues: [Int: Double] = [:]
    @ObservationIgnored private let progressLock = NSLock()
    /// Timer that batches progress into the observable snapshot
    @ObservationIgnored private var progressTimer: Timer?
    /// Number of in-flight downloads — incremented synchronously, so concurrent calls
    /// to startNextIfNeeded can't exceed the limit.
    @ObservationIgnored private var inFlightCount: Int = 0
    /// Tracks task IDs that successfully saved a file in didFinishDownloadingTo
    @ObservationIgnored private var successfulSaves: Set<Int> = []
    /// Notification observer tokens for cleanup
    @ObservationIgnored private var lifecycleObservers: [Any] = []

    // MARK: - Paths

    nonisolated private static var downloadsDirectory: URL {
        let appSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Ondu/Downloads", isDirectory: true)
    }

    nonisolated private static var pendingDirectory: URL {
        downloadsDirectory.appendingPathComponent(".pending", isDirectory: true)
    }

    // MARK: - Init

    init(musicLibrary: MusicLibrary, settings: SettingsStore) {
        self.musicLibrary = musicLibrary
        self.settings = settings
        super.init()
        _ = backgroundSession  // reconnect to any in-flight background tasks
        processPendingCompletions()
        observeAppLifecycle()
    }

    /// Convenience init used by tests and legacy call sites that already have auth available.
    convenience init(baseURL: URL, sessionToken: String, musicLibrary: MusicLibrary, settings: SettingsStore) {
        self.init(musicLibrary: musicLibrary, settings: settings)
        configure(baseURL: baseURL, sessionToken: sessionToken)
    }

    /// Updates current auth. Safe to call repeatedly (e.g. after re-auth). Does not cancel active downloads —
    /// any in-flight request keeps its original Bearer token, and only new/retried requests use the new one.
    func configure(baseURL: URL, sessionToken: String) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
    }

    /// Clears auth state and cancels everything in-flight + queued. Called on logout.
    /// The service stays alive (URLSession continues to exist with its background identifier) so that
    /// the next login can simply call `configure(...)` without creating a second session with the same id.
    func clearAuth() {
        cancelAll()
        failedDownloads.removeAll()
        baseURL = nil
        sessionToken = nil
    }

    // MARK: - Public API

    func download(track: Track, album: Album, artist: Artist) {
        guard !musicLibrary.isDownloaded(trackId: track.id),
            !isDownloading(trackId: track.id),
            !isQueued(trackId: track.id)
        else { return }

        let info = DownloadInfo(track: track, album: album, artist: artist)
        pendingQueue.append(info)
        startNextIfNeeded()
    }

    func download(album: Album, artist: Artist) {
        guard let tracks = album.tracks else { return }
        for track in tracks {
            download(track: track, album: album, artist: artist)
        }
    }

    func hasUndownloadedTracks(library: MusicLibrary) -> Bool {
        let artists = library.allArtists()
        for artist in artists {
            let albums = library.albumsWithTracksForArtist(artist.id)
            for album in albums {
                guard let tracks = album.tracks else { continue }
                for track in tracks {
                    if !musicLibrary.isDownloaded(trackId: track.id),
                        !isDownloading(trackId: track.id),
                        !isQueued(trackId: track.id)
                    {
                        return true
                    }
                }
            }
        }
        return false
    }

    func downloadAll(library: MusicLibrary) {
        // Membership resolved up front. Per track this used to run a SwiftData fetch
        // (isDownloaded) plus a linear scan of the pending queue (isQueued), so a full
        // library was thousands of queries and a quadratic scan — enough to hang the app
        // on the click that started it.
        var seen = library.downloadedTrackIds()
        seen.formUnion(activeDownloads.keys)
        seen.formUnion(pendingQueue.map(\.track.id))

        var queued: [DownloadInfo] = []
        for artist in library.allArtists() {
            for album in library.albumsWithTracksForArtist(artist.id) {
                guard let tracks = album.tracks else { continue }
                for track in tracks where !seen.contains(track.id) {
                    seen.insert(track.id)
                    queued.append(DownloadInfo(track: track, album: album, artist: artist))
                }
            }
        }
        pendingQueue.append(contentsOf: queued)
        startNextIfNeeded()
    }

    func downloadTracks(ids trackIds: Set<UUID>, library: MusicLibrary) {
        guard !trackIds.isEmpty else { return }
        let artists = library.allArtists()
        for artist in artists {
            let albums = library.albumsWithTracksForArtist(artist.id)
            for album in albums {
                guard let tracks = album.tracks else { continue }
                for track in tracks where trackIds.contains(track.id) {
                    guard !musicLibrary.isDownloaded(trackId: track.id),
                        !isDownloading(trackId: track.id),
                        !isQueued(trackId: track.id)
                    else { continue }
                    pendingQueue.append(DownloadInfo(track: track, album: album, artist: artist))
                }
            }
        }
        startNextIfNeeded()
    }

    // MARK: - Per-track controls

    func cancelDownload(trackId: UUID) {
        pendingQueue.removeAll { $0.track.id == trackId }

        if let phase = trackPhases.removeValue(forKey: trackId) {
            switch phase {
            case .downloading(let task, let taskId, _):
                task.cancel()
                taskIdToTrackId.removeValue(forKey: taskId)
                inFlightCount -= 1
            case .paused:
                break
            }
        }
        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    func pauseDownload(trackId: UUID) {
        guard let phase = trackPhases[trackId], phase.isInFlight else { return }

        switch phase {
        case .downloading(let task, let taskId, let info):
            task.cancel()
            taskIdToTrackId.removeValue(forKey: taskId)
            trackPhases[trackId] = .paused(info: info)
            activeDownloads[trackId]?.isPaused = true
            inFlightCount -= 1
        case .paused:
            break
        }
    }

    func resumeDownload(trackId: UUID) {
        guard case .paused(let info) = trackPhases[trackId] else { return }
        trackPhases.removeValue(forKey: trackId)

        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }

        if inFlightCount < settings.maxConcurrentDownloads {
            startTask(info: info)
        } else {
            pendingQueue.insert(info, at: 0)
        }
    }

    // MARK: - Bulk controls

    func pauseAll() {
        isPaused = true
        let activeIds = trackPhases.filter { $0.value.isInFlight }.map(\.key)
        for trackId in activeIds {
            pauseDownload(trackId: trackId)
        }
    }

    func resumeAll() {
        isPaused = false
        let pausedIds = trackPhases.filter {
            if case .paused = $0.value { return true }
            return false
        }.map(\.key)
        for trackId in pausedIds {
            resumeDownload(trackId: trackId)
        }
        startNextIfNeeded()
    }

    func cancelAll() {
        isPaused = false
        for (_, phase) in trackPhases {
            switch phase {
            case .downloading(let task, _, _): task.cancel()
            case .paused: break
            }
        }
        trackPhases.removeAll()
        taskIdToTrackId.removeAll()
        activeDownloads.removeAll()
        activeDownloadOrder.removeAll()
        pendingQueue.removeAll()
        inFlightCount = 0
        progressValues.removeAll()
        progressSnapshot.removeAll()
        stopProgressTimerIfIdle()
    }

    // MARK: - Query

    func isDownloading(trackId: UUID) -> Bool {
        activeDownloads[trackId] != nil
    }

    func isQueued(trackId: UUID) -> Bool {
        pendingQueue.contains { $0.track.id == trackId }
    }

    func isAlbumDownloading(albumId: UUID) -> Bool {
        activeDownloads.values.contains { $0.albumId == albumId } || pendingQueue.contains { $0.album.id == albumId }
    }

    func cancelAlbumDownloads(albumId: UUID) {
        pendingQueue.removeAll { $0.album.id == albumId }

        let trackIds = activeDownloads.filter { $0.value.albumId == albumId }.map(\.key)
        for trackId in trackIds {
            cancelDownload(trackId: trackId)
        }
    }

    var hasActivity: Bool {
        !activeDownloads.isEmpty || !pendingQueue.isEmpty || !failedDownloads.isEmpty
    }

    // MARK: - Internal queue management

    /// Minimum free disk space (in bytes) required to start new downloads.
    private static let minimumFreeDiskSpace: Int64 = 100 * 1024 * 1024  // 100 MB

    /// Cached disk space value and timestamp to avoid frequent filesystem queries.
    @ObservationIgnored private var lastDiskSpaceCheck: (space: Int64, time: Date) = (Int64.max, .distantPast)
    private static let diskSpaceCheckInterval: TimeInterval = 30

    /// Starts tasks from the pending queue up to the concurrency limit.
    private func startNextIfNeeded() {
        guard !isPaused else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled, !ignoresLowPowerMode {
            downloadsPausedReason = .lowPowerMode
            #if DEBUG
            print("DownloadService: not starting — Low Power Mode is on (\(pendingQueue.count) queued)")
            #endif
            return
        }

        if cachedAvailableDiskSpace() < Self.minimumFreeDiskSpace {
            downloadsPausedReason = .lowDiskSpace
            #if DEBUG
            print("DownloadService: not starting — free disk below \(Self.minimumFreeDiskSpace) bytes")
            #endif
            return
        }

        downloadsPausedReason = nil

        while !pendingQueue.isEmpty, inFlightCount < settings.maxConcurrentDownloads {
            let next = pendingQueue.removeFirst()
            if musicLibrary.isDownloaded(trackId: next.track.id) { continue }
            startTask(info: next)
        }
    }

    private func cachedAvailableDiskSpace() -> Int64 {
        if Date().timeIntervalSince(lastDiskSpaceCheck.time) < Self.diskSpaceCheckInterval {
            return lastDiskSpaceCheck.space
        }
        let space = Self.availableDiskSpace()
        lastDiskSpaceCheck = (space, Date())
        return space
    }

    nonisolated private static func availableDiskSpace() -> Int64 {
        guard let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else {
            return Int64.max
        }
        return capacity
    }

    /// Creates and resumes a URLSession download task.
    private func startTask(info: DownloadInfo) {
        inFlightCount += 1
        activeDownloads[info.track.id] = DownloadState(
            trackName: info.track.name,
            artistName: info.artist.name,
            albumId: info.album.id
        )
        activeDownloadOrder.append(info.track.id)
        progressValues[info.track.id] = 0
        startProgressTimerIfNeeded()

        let preset = settings.downloadPreset(for: info.track.mimetype)?.id

        guard let downloadURL = URL(string: info.track.downloadUrl),
            var comps = URLComponents(url: downloadURL, resolvingAgainstBaseURL: false)
        else {
            inFlightCount -= 1
            activeDownloads.removeValue(forKey: info.track.id)
            activeDownloadOrder.removeAll { $0 == info.track.id }
            return
        }
        if let preset {
            var queryItems = comps.queryItems ?? []
            queryItems.append(URLQueryItem(name: "transcode", value: "1"))
            queryItems.append(URLQueryItem(name: "preset", value: preset))
            comps.queryItems = queryItems
        }
        guard let url = comps.url else {
            inFlightCount -= 1
            activeDownloads.removeValue(forKey: info.track.id)
            activeDownloadOrder.removeAll { $0 == info.track.id }
            return
        }
        startDownloadTask(info: info, url: url)
    }

    /// Starts the actual URLSession download task for a given URL.
    private func startDownloadTask(info: DownloadInfo, url: URL) {
        guard let request = authorizedRequest(url) else {
            cleanupUnstarted(trackId: info.track.id, reason: "Not authenticated")
            return
        }
        let session = isInForeground ? foregroundSession : backgroundSession
        let task = session.downloadTask(with: request)

        let metadata = TaskMetadata(
            trackId: info.track.id,
            artistId: info.artist.id,
            albumId: info.album.id,
            mimetype: info.track.mimetype,
            trackName: info.track.name
        )
        task.taskDescription = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)

        let taskId = task.taskIdentifier
        trackPhases[info.track.id] = .downloading(task: task, taskId: taskId, info: info)
        taskIdToTrackId[taskId] = info.track.id
        task.resume()
    }

    /// Handles a 401 response: re-queue the download for after re-auth, pause new starts, notify UI.
    private func handleUnauthorized(requeue info: DownloadInfo) {
        let trackId = info.track.id
        let phase = trackPhases.removeValue(forKey: trackId)
        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        if case .downloading(_, let taskId, _) = phase {
            taskIdToTrackId.removeValue(forKey: taskId)
            progressLock.lock()
            taskProgressValues.removeValue(forKey: taskId)
            progressLock.unlock()
        }
        inFlightCount -= 1
        pendingQueue.insert(info, at: 0)
        isPaused = true
        stopProgressTimerIfIdle()
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }

    /// Cleans up a download that failed before it had a URLSession task.
    private func cleanupUnstarted(trackId: UUID, reason: String? = nil) {
        let phase = trackPhases.removeValue(forKey: trackId)
        let state = activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        inFlightCount -= 1
        if let reason, let phase, let state {
            addFailedDownload(
                trackId: trackId, trackName: state.trackName, artistName: state.artistName, info: phase.info,
                reason: reason)
        }
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    private func cleanupTask(trackId: UUID, taskId: Int, reason: String? = nil) {
        // Guard: only clean up if this task is still tracked (prevents double-cleanup
        // when migrateToBackground already cleaned up a cancelled task)
        guard taskIdToTrackId.removeValue(forKey: taskId) != nil else { return }
        let phase = trackPhases.removeValue(forKey: trackId)
        let state = activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        progressLock.lock()
        taskProgressValues.removeValue(forKey: taskId)
        progressLock.unlock()
        inFlightCount -= 1
        if let reason, let state, let phase {
            addFailedDownload(
                trackId: trackId, trackName: state.trackName, artistName: state.artistName, info: phase.info,
                reason: reason)
        }
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    private func addFailedDownload(
        trackId: UUID, trackName: String, artistName: String, info: DownloadInfo, reason: String
    ) {
        // Don't add duplicates
        guard !failedDownloads.contains(where: { $0.id == trackId }) else { return }
        failedDownloads.append(
            FailedDownload(
                id: trackId, trackName: trackName, artistName: artistName, info: info, reason: reason
            ))
    }

    func retryDownload(_ failed: FailedDownload) {
        failedDownloads.removeAll { $0.id == failed.id }
        // Unmark in case a previous bad download marked it as downloaded
        musicLibrary.markUndownloaded(trackId: failed.id)
        pendingQueue.append(failed.info)
        startNextIfNeeded()
    }

    func dismissFailedDownload(_ failed: FailedDownload) {
        failedDownloads.removeAll { $0.id == failed.id }
    }

    func clearFailedDownloads() {
        failedDownloads.removeAll()
    }

    /// Processes any pending completions and migrates downloads to foreground session.
    func resumeOnForeground() {
        isInForeground = true
        processPendingCompletions()

        // Migrate in-flight background tasks to the faster foreground session
        for (trackId, phase) in trackPhases {
            guard case .downloading(let task, let taskId, let info) = phase else { continue }
            task.cancel()
            taskIdToTrackId.removeValue(forKey: taskId)
            trackPhases.removeValue(forKey: trackId)
            pendingQueue.insert(info, at: 0)
            activeDownloads.removeValue(forKey: trackId)
            activeDownloadOrder.removeAll { $0 == trackId }
            progressValues.removeValue(forKey: trackId)
            inFlightCount -= 1
        }
        startNextIfNeeded()
    }

    // MARK: - App lifecycle (foreground → background session switching)

    private func observeAppLifecycle() {
        #if os(iOS)
        let backgroundName = UIApplication.willResignActiveNotification
        let foregroundName = UIApplication.didBecomeActiveNotification
        #else
        let backgroundName = NSApplication.willResignActiveNotification
        let foregroundName = NSApplication.didBecomeActiveNotification
        #endif

        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: backgroundName, object: nil, queue: .main
            ) { [weak self] _ in self?.migrateToBackground() }
        )
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: foregroundName, object: nil, queue: .main
            ) { [weak self] _ in self?.resumeOnForeground() }
        )
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
            ) { [weak self] _ in self?.startNextIfNeeded() }
        )
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// App is going to background — move in-flight foreground tasks to background session.
    private func migrateToBackground() {
        isInForeground = false

        for (trackId, phase) in trackPhases {
            switch phase {
            case .downloading(let task, let taskId, let info):
                task.cancel()
                taskIdToTrackId.removeValue(forKey: taskId)
                pendingQueue.insert(info, at: 0)
            case .paused:
                continue  // Leave paused downloads alone
            }
            trackPhases.removeValue(forKey: trackId)
            activeDownloads.removeValue(forKey: trackId)
            activeDownloadOrder.removeAll { $0 == trackId }
            progressValues.removeValue(forKey: trackId)
            inFlightCount -= 1
        }
        startNextIfNeeded()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier

        if let httpResponse = downloadTask.response as? HTTPURLResponse,
            !(200...299).contains(httpResponse.statusCode)
        {
            // Don't save — didCompleteWithError will handle the failure
            return
        }

        guard let descriptionData = downloadTask.taskDescription?.data(using: .utf8),
            let metadata = try? JSONDecoder().decode(TaskMetadata.self, from: descriptionData)
        else {
            return
        }

        // Use response Content-Type if available (may differ from original when transcoding)
        let responseMimetype =
            (downloadTask.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type") ?? metadata.mimetype

        let saved = saveDownloadedFile(metadata: metadata, mimetype: responseMimetype, tempLocation: location)

        // Validate file was saved and has reasonable size (> 1KB)
        guard let saved, saved.size > 1024 else {
            #if DEBUG
            print("DownloadService: file save failed or too small for \(metadata.trackName)")
            #endif
            return
        }

        // Write pending completion for SwiftData update on foreground
        writePendingCompletion(trackId: metadata.trackId, relativePath: saved.path, downloadedFileSize: saved.size)

        Task { @MainActor in
            self.successfulSaves.insert(taskId)
            self.musicLibrary.markDownloaded(
                trackId: metadata.trackId, relativePath: saved.path, downloadedFileSize: saved.size)
            self.removePendingCompletion(trackId: metadata.trackId)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        let progress =
            totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        progressLock.lock()
        taskProgressValues[taskId] = progress
        progressLock.unlock()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let taskId = task.taskIdentifier
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode

        let retryAfter: TimeInterval? =
            if [429, 503].contains(statusCode),
                let header = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"),
                let seconds = Double(header)
            { seconds } else { nil }

        Task { @MainActor in
            guard let trackId = self.taskIdToTrackId[taskId],
                case .downloading(_, _, let info) = self.trackPhases[trackId]
            else { return }

            if statusCode == 401 {
                self.handleUnauthorized(requeue: info)
                return
            }

            if [408, 429, 502, 503, 504].contains(statusCode), info.retryCount < 3 {
                let delay = retryAfter ?? 5
                #if DEBUG
                print(
                    "DownloadService: server busy for \(info.track.name), retrying in \(Int(delay))s (attempt \(info.retryCount + 1)/3)"
                )
                #endif
                var retryInfo = info
                retryInfo.retryCount += 1
                // Remove task tracking but don't decrement inFlightCount or start next —
                // this slot stays reserved for the retry
                trackPhases.removeValue(forKey: trackId)
                taskIdToTrackId.removeValue(forKey: taskId)
                progressValues.removeValue(forKey: trackId)
                // Re-queue after delay, then release the slot
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    self.activeDownloads.removeValue(forKey: trackId)
                    self.activeDownloadOrder.removeAll { $0 == trackId }
                    self.inFlightCount -= 1
                    self.pendingQueue.insert(retryInfo, at: 0)
                    self.stopProgressTimerIfIdle()
                    self.startNextIfNeeded()
                }
                return
            }

            if let statusCode, !(200...299).contains(statusCode) {
                #if DEBUG
                print("DownloadService: HTTP \(statusCode) for \(info.track.name)")
                #endif
                cleanupTask(trackId: trackId, taskId: taskId, reason: "Server error (HTTP \(statusCode))")
                return
            }

            guard let error else {
                // Check if didFinishDownloadingTo actually saved the file
                if self.successfulSaves.remove(taskId) != nil {
                    cleanupTask(trackId: trackId, taskId: taskId)
                } else {
                    #if DEBUG
                    print("DownloadService: download completed but file was not saved for \(info.track.name)")
                    #endif
                    cleanupTask(trackId: trackId, taskId: taskId, reason: "Download failed — file could not be saved")
                }
                return
            }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }

            #if DEBUG
            print("DownloadService: error detail for \(info.track.name):")
            print("  code: \(nsError.code) domain: \(nsError.domain)")
            print("  userInfo: \(nsError.userInfo)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print(
                    "  underlying: code=\(underlying.code) domain=\(underlying.domain) \(underlying.localizedDescription)"
                )
            }
            if let response = task.response as? HTTPURLResponse {
                print("  response: HTTP \(response.statusCode) headers=\(response.allHeaderFields)")
            } else {
                print("  response: nil")
            }
            #endif

            // Retry transient network errors
            let retryableErrors = [
                NSURLErrorUnknown,  // -1
                NSURLErrorTimedOut,  // -1001
                NSURLErrorNetworkConnectionLost,  // -1005
            ]
            if retryableErrors.contains(nsError.code), info.retryCount < 3 {
                var retryInfo = info
                retryInfo.retryCount += 1
                #if DEBUG
                print(
                    "DownloadService: transient error for \(info.track.name), retrying (attempt \(retryInfo.retryCount)/3, code: \(nsError.code))"
                )
                #endif
                pendingQueue.insert(retryInfo, at: 0)
                cleanupTask(trackId: trackId, taskId: taskId)
                return
            }

            #if DEBUG
            print("DownloadService: download failed for \(info.track.name): \(error)")
            #endif
            cleanupTask(trackId: trackId, taskId: taskId, reason: error.localizedDescription)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            processPendingCompletions()
            startNextIfNeeded()
            #if os(iOS)
            let handler = BackgroundSessionDelegate.pendingCompletionHandler
            BackgroundSessionDelegate.pendingCompletionHandler = nil
            handler?()
            #endif
        }
    }

    // MARK: - File management

    /// Moves downloaded file directly to its final path. Returns (relativePath, fileSize) or nil.
    nonisolated private func saveDownloadedFile(metadata: TaskMetadata, mimetype: String, tempLocation: URL) -> (
        path: String, size: Int64
    )? {
        let fm = FileManager.default
        let dir = Self.downloadsDirectory
            .appendingPathComponent(metadata.artistId.uuidString, isDirectory: true)
            .appendingPathComponent(metadata.albumId.uuidString, isDirectory: true)

        let ext = extensionFromMimetype(mimetype)
        let destURL = dir.appendingPathComponent("\(metadata.trackId.uuidString).\(ext)")
        let relativePath =
            "Ondu/Downloads/\(metadata.artistId.uuidString)/\(metadata.albumId.uuidString)/\(metadata.trackId.uuidString).\(ext)"

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tempLocation, to: destURL)
            let size = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0

            // Validate M4A/MP4 files have a moov atom (required for playback)
            if ext == "m4a" || ext == "mp4" {
                guard Self.hasMoovAtom(at: destURL) else {
                    #if DEBUG
                    print("DownloadService: corrupt M4A (missing moov) for \(metadata.trackName), size=\(size)")
                    Self.debugAtoms(at: destURL)
                    #endif
                    try? fm.removeItem(at: destURL)
                    return nil
                }
            }

            return (relativePath, size)
        } catch {
            #if DEBUG
            print("DownloadService: failed to save file for \(metadata.trackName): \(error)")
            #endif
            return nil
        }
    }

    /// Debug: prints all top-level MP4 atoms found in the file.
    nonisolated private static func debugAtoms(at url: URL) {
        #if DEBUG
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            print("  debugAtoms: cannot open file")
            return
        }
        defer { try? handle.close() }

        var offset: UInt64 = 0
        while let header = try? handle.read(upToCount: 8), header.count == 8 {
            let size = UInt32(header[0]) << 24 | UInt32(header[1]) << 16 | UInt32(header[2]) << 8 | UInt32(header[3])
            let type = String(data: header[4..<8], encoding: .ascii) ?? "????"
            print("  atom: \(type) size=\(size) offset=\(offset)")
            guard size >= 8 else { break }
            offset += UInt64(size)
            try? handle.seek(toOffset: offset)
        }
        #endif
    }

    /// Checks if an MP4/M4A file contains a moov atom (required for playback).
    nonisolated private static func hasMoovAtom(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        while let header = try? handle.read(upToCount: 8), header.count == 8 {
            let size = UInt32(header[0]) << 24 | UInt32(header[1]) << 16 | UInt32(header[2]) << 8 | UInt32(header[3])
            let type = String(data: header[4..<8], encoding: .ascii) ?? ""
            if type == "moov" { return true }

            if size == 0 {
                // size=0 means "extends to EOF" (common for mdat without faststart).
                // moov may still follow the actual data — scan the tail of the file.
                guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else { return false }
                let scanSize = min(fileSize, 512 * 1024)
                try? handle.seek(toOffset: fileSize - scanSize)
                guard let tail = try? handle.read(upToCount: Int(scanSize)), tail.count >= 8 else { return false }
                let moov: [UInt8] = [0x6D, 0x6F, 0x6F, 0x76]  // "moov"
                for i in 4..<tail.count where tail[i] == moov[0] {
                    if i + 3 < tail.count && tail[i + 1] == moov[1] && tail[i + 2] == moov[2] && tail[i + 3] == moov[3]
                    {
                        return true
                    }
                }
                return false
            }

            guard size >= 8 else { return false }
            let offset = try? handle.offset()
            guard let currentOffset = offset else { return false }
            try? handle.seek(toOffset: currentOffset + UInt64(size) - 8)
        }
        return false
    }

    /// Writes a pending completion record to disk. If the app is suspended before
    /// SwiftData can be updated, this record is processed on next foreground.
    nonisolated private func writePendingCompletion(trackId: UUID, relativePath: String, downloadedFileSize: Int64) {
        let fm = FileManager.default
        let dir = Self.pendingDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let record = PendingCompletion(
            trackId: trackId, relativePath: relativePath, downloadedFileSize: downloadedFileSize)
        let file = dir.appendingPathComponent("\(trackId.uuidString).json")
        try? JSONEncoder().encode(record).write(to: file)
    }

    /// Removes a pending completion record after SwiftData has been updated.
    private func removePendingCompletion(trackId: UUID) {
        let file = Self.pendingDirectory.appendingPathComponent("\(trackId.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    /// Scans for pending completion records and updates SwiftData.
    /// Called on init and when returning to foreground. Runs on MainActor
    /// (implicit from build setting) since it touches MusicLibrary's mainContext.
    func processPendingCompletions() {
        let fm = FileManager.default
        let dir = Self.pendingDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let record = try? JSONDecoder().decode(PendingCompletion.self, from: data)
            else {
                try? fm.removeItem(at: file)
                continue
            }

            if !musicLibrary.isDownloaded(trackId: record.trackId) {
                musicLibrary.markDownloaded(
                    trackId: record.trackId, relativePath: record.relativePath,
                    downloadedFileSize: record.downloadedFileSize)
            }
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Progress timer

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.progressLock.lock()
            let taskValues = self.taskProgressValues
            self.progressLock.unlock()
            var snapshot: [UUID: Double] = [:]
            for (taskId, progress) in taskValues {
                if let trackId = self.taskIdToTrackId[taskId] {
                    snapshot[trackId] = progress
                }
            }
            self.progressSnapshot = snapshot
        }
    }

    private func stopProgressTimerIfIdle() {
        guard activeDownloads.isEmpty else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        progressSnapshot.removeAll()
        progressLock.lock()
        taskProgressValues.removeAll()
        progressLock.unlock()
    }

    // MARK: - Helpers

    nonisolated private func extensionFromMimetype(_ mimetype: String) -> String {
        AudioFormat.fileExtension(for: mimetype)
    }

    // MARK: - Test Helpers

    /// Exposes hasMoovAtom for unit tests via @testable import.
    nonisolated static func testHasMoovAtom(at url: URL) -> Bool {
        hasMoovAtom(at: url)
    }
}
