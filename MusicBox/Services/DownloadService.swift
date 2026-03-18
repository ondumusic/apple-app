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

    // MARK: - Private

    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let baseURL: URL

    @ObservationIgnored private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.musicbox.downloads.delegate"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    /// Background session — survives app suspension/termination
    @ObservationIgnored private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.musicbox.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpAdditionalHeaders = sessionHeaders
        config.timeoutIntervalForRequest = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    /// Foreground session — faster (no IPC overhead), used while app is active
    @ObservationIgnored private lazy var foregroundSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = sessionHeaders
        config.timeoutIntervalForRequest = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    /// Lightweight session for transcode prepare requests (no delegate needed)
    @ObservationIgnored private lazy var prepareSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = sessionHeaders
        config.timeoutIntervalForRequest = 300
        return URLSession(configuration: config)
    }()

    @ObservationIgnored private let sessionHeaders: [String: String]
    /// Whether the app is currently in the foreground
    @ObservationIgnored private var isInForeground: Bool = true

    /// Maps URLSession task identifier → download info (for UI state management)
    @ObservationIgnored private var taskDownloads: [Int: DownloadInfo] = [:]
    /// Maps track ID → URLSession task identifier
    @ObservationIgnored private var trackIdToTaskId: [UUID: Int] = [:]
    /// Maps track ID → active URLSessionDownloadTask (for pause support)
    @ObservationIgnored private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Maps track ID → active prepare data task (for cancellation during prepare phase)
    @ObservationIgnored private var prepareTasks: [UUID: URLSessionDataTask] = [:]
    /// Maps track ID → download info for tracks in the prepare phase (needed for re-queuing)
    @ObservationIgnored private var prepareInfos: [UUID: DownloadInfo] = [:]
    /// Stores info for paused downloads
    @ObservationIgnored private var pausedDownloads: [UUID: DownloadInfo] = [:]
    /// Raw progress values — not observable, updated on every delegate callback
    @ObservationIgnored private var progressValues: [UUID: Double] = [:]
    /// Timer that batches progress into the observable snapshot
    @ObservationIgnored private var progressTimer: Timer?
    /// Number of in-flight downloads — incremented synchronously, so concurrent calls
    /// to startNextIfNeeded can't exceed the limit.
    @ObservationIgnored private var inFlightCount: Int = 0
    /// Tracks task IDs that successfully saved a file in didFinishDownloadingTo
    @ObservationIgnored private var successfulSaves: Set<Int> = []

    // MARK: - Paths

    nonisolated private static var downloadsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MusicBox/Downloads", isDirectory: true)
    }

    nonisolated private static var pendingDirectory: URL {
        downloadsDirectory.appendingPathComponent(".pending", isDirectory: true)
    }

    // MARK: - Init

    init(baseURL: URL, sessionToken: String, musicLibrary: MusicLibrary, settings: SettingsStore) {
        self.baseURL = baseURL
        self.musicLibrary = musicLibrary
        self.settings = settings
        self.sessionHeaders = ["Authorization": "Bearer \(sessionToken)"]
        super.init()
        _ = backgroundSession // reconnect to any in-flight background tasks
        processPendingCompletions()
        observeAppLifecycle()
    }

    // MARK: - Public API

    func download(track: Track, album: Album, artist: Artist) {
        guard !musicLibrary.isDownloaded(trackId: track.id),
              !isDownloading(trackId: track.id),
              !isQueued(trackId: track.id) else { return }

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
                       !isQueued(trackId: track.id) {
                        return true
                    }
                }
            }
        }
        return false
    }

    func downloadAll(library: MusicLibrary) {
        let artists = library.allArtists()
        for artist in artists {
            let albums = library.albumsWithTracksForArtist(artist.id)
            for album in albums {
                guard let tracks = album.tracks else { continue }
                for track in tracks {
                    guard !musicLibrary.isDownloaded(trackId: track.id),
                          !isDownloading(trackId: track.id),
                          !isQueued(trackId: track.id) else { continue }
                    pendingQueue.append(DownloadInfo(track: track, album: album, artist: artist))
                }
            }
        }
        startNextIfNeeded()
    }

    // MARK: - Per-track controls

    func cancelDownload(trackId: UUID) {
        pendingQueue.removeAll { $0.track.id == trackId }
        pausedDownloads.removeValue(forKey: trackId)
        prepareTasks.removeValue(forKey: trackId)?.cancel()
        prepareInfos.removeValue(forKey: trackId)

        if let task = activeTasks.removeValue(forKey: trackId) {
            let taskId = task.taskIdentifier
            task.cancel()
            taskDownloads.removeValue(forKey: taskId)
            trackIdToTaskId.removeValue(forKey: trackId)
            inFlightCount -= 1
        } else if activeDownloads[trackId] != nil {
            // In prepare phase (no URLSession task yet)
            inFlightCount -= 1
        }
        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    func pauseDownload(trackId: UUID) {
        // Handle prepare phase
        if let prepareTask = prepareTasks.removeValue(forKey: trackId) {
            prepareTask.cancel()
            if let info = prepareInfos.removeValue(forKey: trackId) {
                pausedDownloads[trackId] = info
                activeDownloads[trackId]?.isPaused = true
                inFlightCount -= 1
            }
            return
        }

        // Handle download phase
        guard let task = activeTasks.removeValue(forKey: trackId),
              let info = taskDownloads[task.taskIdentifier] else { return }

        let taskId = task.taskIdentifier
        task.cancel()

        taskDownloads.removeValue(forKey: taskId)
        trackIdToTaskId.removeValue(forKey: trackId)
        inFlightCount -= 1

        pausedDownloads[trackId] = info
        activeDownloads[trackId]?.isPaused = true
    }

    func resumeDownload(trackId: UUID) {
        guard let info = pausedDownloads.removeValue(forKey: trackId) else { return }

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
        let activeIds = Array(trackIdToTaskId.keys)
        for trackId in activeIds {
            pauseDownload(trackId: trackId)
        }
    }

    func resumeAll() {
        isPaused = false
        let pausedIds = Array(pausedDownloads.keys)
        for trackId in pausedIds {
            resumeDownload(trackId: trackId)
        }
        startNextIfNeeded()
    }

    func cancelAll() {
        isPaused = false
        for (_, task) in prepareTasks { task.cancel() }
        prepareTasks.removeAll()
        prepareInfos.removeAll()
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        taskDownloads.removeAll()
        trackIdToTaskId.removeAll()
        activeDownloads.removeAll()
        activeDownloadOrder.removeAll()
        pendingQueue.removeAll()
        pausedDownloads.removeAll()
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
        activeDownloads.values.contains { $0.albumId == albumId } ||
        pendingQueue.contains { $0.album.id == albumId }
    }

    var hasActivity: Bool {
        !activeDownloads.isEmpty || !pendingQueue.isEmpty || !failedDownloads.isEmpty
    }

    // MARK: - Internal queue management

    /// Starts tasks from the pending queue up to the concurrency limit.
    private func startNextIfNeeded() {
        guard !isPaused else { return }

        while !pendingQueue.isEmpty, inFlightCount < settings.maxConcurrentDownloads {
            let next = pendingQueue.removeFirst()
            if musicLibrary.isDownloaded(trackId: next.track.id) { continue }
            startTask(info: next)
        }
    }

    /// Creates and resumes a URLSession download task.
    private func startTask(info: DownloadInfo) {
        let quality = settings.downloadQuality

        inFlightCount += 1
        activeDownloads[info.track.id] = DownloadState(
            trackName: info.track.name,
            artistName: info.artist.name,
            albumId: info.album.id
        )
        activeDownloadOrder.append(info.track.id)
        progressValues[info.track.id] = 0
        startProgressTimerIfNeeded()

        // Determine effective preset: transcode unsupported formats even when quality is "original"
        let needsTranscode = quality != .original || !AudioFormat.isAVPlayerSupported(info.track.mimetype)
        let preset = quality != .original ? quality.rawValue : "default_aac"

        if needsTranscode, isInForeground {
            // Two-stage: prepare transcode via SSE, then download cached file with progress
            prepareAndDownload(info: info, preset: preset)
        } else {
            // Background transcoded or original: download directly (no SSE prepare)
            guard let downloadURL = URL(string: info.track.downloadUrl),
                  var comps = URLComponents(url: downloadURL, resolvingAgainstBaseURL: false) else {
                inFlightCount -= 1
                activeDownloads.removeValue(forKey: info.track.id)
                activeDownloadOrder.removeAll { $0 == info.track.id }
                return
            }
            if needsTranscode {
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
    }

    /// Kicks off an async transcode prepare, then starts the download on completion.
    private func prepareAndDownload(info: DownloadInfo, preset: String) {
        let trackId = info.track.id
        let downloadUrlString = info.track.downloadUrl
        let session = prepareSession
        prepareInfos[trackId] = info

        // Build prepare URL
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/transcode/\(trackId.uuidString.lowercased())"
        components.queryItems = [URLQueryItem(name: "preset", value: preset)]
        guard let prepareURL = components.url else {
            cleanupPrepare(trackId: trackId, reason: "Invalid URL")
            return
        }

        var request = URLRequest(url: prepareURL)
        request.timeoutInterval = 300

        // Use a completion-based data task to avoid Task/async entirely
        let dataTask = session.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // If prepareTasks no longer contains this track, the request was cancelled
                // by migrateToBackground/pause/cancel — ignore this stale callback
                guard prepareTasks.removeValue(forKey: trackId) != nil else { return }
                prepareInfos.removeValue(forKey: trackId)
                guard activeDownloads[trackId] != nil else { return }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) }
                guard error == nil, (200...299).contains(statusCode), let body else {
                    let msg = error?.localizedDescription ?? "HTTP \(statusCode)"
                    self.cleanupPrepare(trackId: trackId, reason: "Transcode failed: \(msg)")
                    return
                }

                // Parse SSE response for file size
                var fileSize: Int64?
                for line in body.components(separatedBy: "\n") {
                    if line.hasPrefix("data: "),
                       let jsonData = line.dropFirst(6).data(using: .utf8),
                       let result = try? JSONDecoder().decode(PrepareResult.self, from: jsonData) {
                        fileSize = result.size
                        break
                    }
                }

                guard let fileSize,
                      let downloadURL = URL(string: downloadUrlString),
                      var comps = URLComponents(url: downloadURL, resolvingAgainstBaseURL: false) else {
                    self.cleanupPrepare(trackId: trackId, reason: "Transcode response invalid")
                    return
                }
                var queryItems = comps.queryItems ?? []
                queryItems.append(URLQueryItem(name: "transcode", value: "1"))
                queryItems.append(URLQueryItem(name: "preset", value: preset))
                comps.queryItems = queryItems
                guard let url = comps.url else {
                    self.cleanupPrepare(trackId: trackId, reason: "Invalid download URL")
                    return
                }
                self.startDownloadTask(info: info, url: url)
            }
        }
        prepareTasks[trackId] = dataTask
        dataTask.resume()
    }

    /// Starts the actual URLSession download task for a given URL.
    private func startDownloadTask(info: DownloadInfo, url: URL) {
        let session = isInForeground ? foregroundSession : backgroundSession
        let task = session.downloadTask(with: url)

        let metadata = TaskMetadata(
            trackId: info.track.id,
            artistId: info.artist.id,
            albumId: info.album.id,
            mimetype: info.track.mimetype,
            trackName: info.track.name
        )
        task.taskDescription = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)

        taskDownloads[task.taskIdentifier] = info
        trackIdToTaskId[info.track.id] = task.taskIdentifier
        activeTasks[info.track.id] = task
        task.resume()
    }

    private nonisolated struct PrepareResult: Decodable {
        let size: Int64
    }

    /// Cleans up a download that failed during the prepare/transcode phase (no URLSession task yet).
    private func cleanupPrepare(trackId: UUID, reason: String? = nil) {
        let info = prepareInfos[trackId]
        prepareTasks.removeValue(forKey: trackId)
        prepareInfos.removeValue(forKey: trackId)
        let state = activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        inFlightCount -= 1
        if let reason, let info, let state {
            addFailedDownload(trackId: trackId, trackName: state.trackName, artistName: state.artistName, info: info, reason: reason)
        }
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    private func cleanupTask(trackId: UUID, taskId: Int, reason: String? = nil) {
        // Guard: only clean up if this task is still tracked (prevents double-cleanup
        // when migrateToBackground already cleaned up a cancelled task)
        guard let info = taskDownloads.removeValue(forKey: taskId) else { return }
        let state = activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        trackIdToTaskId.removeValue(forKey: trackId)
        activeTasks.removeValue(forKey: trackId)
        progressValues.removeValue(forKey: trackId)
        inFlightCount -= 1
        if let reason, let state {
            addFailedDownload(trackId: trackId, trackName: state.trackName, artistName: state.artistName, info: info, reason: reason)
        }
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    private func addFailedDownload(trackId: UUID, trackName: String, artistName: String, info: DownloadInfo, reason: String) {
        // Don't add duplicates
        guard !failedDownloads.contains(where: { $0.id == trackId }) else { return }
        failedDownloads.append(FailedDownload(
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
        let inflight = activeTasks
        for (trackId, task) in inflight {
            let taskId = task.taskIdentifier
            task.cancel()
            if let info = taskDownloads.removeValue(forKey: taskId) {
                pendingQueue.insert(info, at: 0)
            }
            trackIdToTaskId.removeValue(forKey: trackId)
            activeTasks.removeValue(forKey: trackId)
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

        NotificationCenter.default.addObserver(
            forName: backgroundName, object: nil, queue: .main
        ) { [weak self] _ in self?.migrateToBackground() }

        NotificationCenter.default.addObserver(
            forName: foregroundName, object: nil, queue: .main
        ) { [weak self] _ in self?.resumeOnForeground() }
    }

    /// App is going to background — move in-flight foreground tasks to background session.
    private func migrateToBackground() {
        isInForeground = false

        // Cancel any in-flight prepare requests and re-queue them
        for (trackId, task) in prepareTasks {
            task.cancel()
            if let info = prepareInfos.removeValue(forKey: trackId) {
                pendingQueue.insert(info, at: 0)
            }
            activeDownloads.removeValue(forKey: trackId)
            activeDownloadOrder.removeAll { $0 == trackId }
            progressValues.removeValue(forKey: trackId)
            inFlightCount -= 1
        }
        prepareTasks.removeAll()

        let inflight = activeTasks

        // Cancel foreground tasks and re-queue them for the background session
        for (trackId, task) in inflight {
            let taskId = task.taskIdentifier
            task.cancel()
            if let info = taskDownloads.removeValue(forKey: taskId) {
                pendingQueue.insert(info, at: 0)
            }
            trackIdToTaskId.removeValue(forKey: trackId)
            activeTasks.removeValue(forKey: trackId)
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
           !(200...299).contains(httpResponse.statusCode) {
            // Don't save — didCompleteWithError will handle the failure
            return
        }

        guard let descriptionData = downloadTask.taskDescription?.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(TaskMetadata.self, from: descriptionData) else {
            return
        }

        // Use response Content-Type if available (may differ from original when transcoding)
        let responseMimetype = (downloadTask.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type") ?? metadata.mimetype

        let saved = saveDownloadedFile(metadata: metadata, mimetype: responseMimetype, tempLocation: location)

        // Validate file was saved and has reasonable size (> 1KB)
        guard let saved, saved.size > 1024 else {
            print("DownloadService: file save failed or too small for \(metadata.trackName)")
            return
        }

        // Write pending completion for SwiftData update on foreground
        writePendingCompletion(trackId: metadata.trackId, relativePath: saved.path, downloadedFileSize: saved.size)

        Task { @MainActor in
            self.successfulSaves.insert(taskId)
            self.musicLibrary.markDownloaded(trackId: metadata.trackId, relativePath: saved.path, downloadedFileSize: saved.size)
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
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        Task { @MainActor in
            guard let info = taskDownloads[taskId] else { return }
            progressValues[info.track.id] = progress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let taskId = task.taskIdentifier
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode

        let retryAfter: TimeInterval? = if [429, 503].contains(statusCode),
            let header = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"),
            let seconds = Double(header) { seconds } else { nil }

        Task { @MainActor in
            guard let info = taskDownloads[taskId] else { return }

            if [408, 429, 502, 503, 504].contains(statusCode), info.retryCount < 3 {
                let delay = retryAfter ?? 5
                print("DownloadService: server busy for \(info.track.name), retrying in \(Int(delay))s (attempt \(info.retryCount + 1)/3)")
                let trackId = info.track.id
                var retryInfo = info
                retryInfo.retryCount += 1
                // Remove task tracking but don't decrement inFlightCount or start next —
                // this slot stays reserved for the retry
                taskDownloads.removeValue(forKey: taskId)
                trackIdToTaskId.removeValue(forKey: trackId)
                activeTasks.removeValue(forKey: trackId)
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
                print("DownloadService: HTTP \(statusCode) for \(info.track.name)")
                cleanupTask(trackId: info.track.id, taskId: taskId, reason: "Server error (HTTP \(statusCode))")
                return
            }

            guard let error else {
                // Check if didFinishDownloadingTo actually saved the file
                if self.successfulSaves.remove(taskId) != nil {
                    cleanupTask(trackId: info.track.id, taskId: taskId)
                } else {
                    print("DownloadService: download completed but file was not saved for \(info.track.name)")
                    cleanupTask(trackId: info.track.id, taskId: taskId, reason: "Download failed — file could not be saved")
                }
                return
            }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }

            print("DownloadService: error detail for \(info.track.name):")
            print("  code: \(nsError.code) domain: \(nsError.domain)")
            print("  userInfo: \(nsError.userInfo)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("  underlying: code=\(underlying.code) domain=\(underlying.domain) \(underlying.localizedDescription)")
            }
            if let response = task.response as? HTTPURLResponse {
                print("  response: HTTP \(response.statusCode) headers=\(response.allHeaderFields)")
            } else {
                print("  response: nil")
            }

            // Retry transient network errors
            let retryableErrors = [
                NSURLErrorUnknown,              // -1
                NSURLErrorTimedOut,              // -1001
                NSURLErrorNetworkConnectionLost, // -1005
            ]
            if retryableErrors.contains(nsError.code), info.retryCount < 3 {
                let trackId = info.track.id
                var retryInfo = info
                retryInfo.retryCount += 1
                print("DownloadService: transient error for \(info.track.name), retrying (attempt \(retryInfo.retryCount)/3, code: \(nsError.code))")
                pendingQueue.insert(retryInfo, at: 0)
                cleanupTask(trackId: trackId, taskId: taskId)
                return
            }

            print("DownloadService: download failed for \(info.track.name): \(error)")
            cleanupTask(trackId: info.track.id, taskId: taskId, reason: error.localizedDescription)
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
    nonisolated private func saveDownloadedFile(metadata: TaskMetadata, mimetype: String, tempLocation: URL) -> (path: String, size: Int64)? {
        let fm = FileManager.default
        let dir = Self.downloadsDirectory
            .appendingPathComponent(metadata.artistId.uuidString, isDirectory: true)
            .appendingPathComponent(metadata.albumId.uuidString, isDirectory: true)

        let ext = extensionFromMimetype(mimetype)
        let destURL = dir.appendingPathComponent("\(metadata.trackId.uuidString).\(ext)")
        let relativePath = "MusicBox/Downloads/\(metadata.artistId.uuidString)/\(metadata.albumId.uuidString)/\(metadata.trackId.uuidString).\(ext)"

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
                    print("DownloadService: corrupt M4A (missing moov) for \(metadata.trackName), size=\(size)")
                    Self.debugAtoms(at: destURL)
                    try? fm.removeItem(at: destURL)
                    return nil
                }
            }

            return (relativePath, size)
        } catch {
            print("DownloadService: failed to save file for \(metadata.trackName): \(error)")
            return nil
        }
    }

    /// Debug: prints all top-level MP4 atoms found in the file.
    nonisolated private static func debugAtoms(at url: URL) {
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
                let moov: [UInt8] = [0x6D, 0x6F, 0x6F, 0x76] // "moov"
                for i in 4 ..< tail.count where tail[i] == moov[0] {
                    if i + 3 < tail.count && tail[i+1] == moov[1] && tail[i+2] == moov[2] && tail[i+3] == moov[3] {
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

        let record = PendingCompletion(trackId: trackId, relativePath: relativePath, downloadedFileSize: downloadedFileSize)
        let file = dir.appendingPathComponent("\(trackId.uuidString).json")
        try? JSONEncoder().encode(record).write(to: file)
    }

    /// Removes a pending completion record after SwiftData has been updated.
    private func removePendingCompletion(trackId: UUID) {
        let file = Self.pendingDirectory.appendingPathComponent("\(trackId.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    /// Scans for pending completion records and updates SwiftData.
    /// Called on init and when returning to foreground.
    func processPendingCompletions() {
        let fm = FileManager.default
        let dir = Self.pendingDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(PendingCompletion.self, from: data) else {
                try? fm.removeItem(at: file)
                continue
            }

            if !musicLibrary.isDownloaded(trackId: record.trackId) {
                musicLibrary.markDownloaded(trackId: record.trackId, relativePath: record.relativePath, downloadedFileSize: record.downloadedFileSize)
            }
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Progress timer

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.progressSnapshot = self?.progressValues ?? [:]
            }
        }
    }

    private func stopProgressTimerIfIdle() {
        guard activeDownloads.isEmpty else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        progressSnapshot.removeAll()
    }

    // MARK: - Helpers

    nonisolated private func extensionFromMimetype(_ mimetype: String) -> String {
        switch mimetype.lowercased() {
        case "audio/mpeg", "audio/mp3": "mp3"
        case "audio/flac": "flac"
        case "audio/x-flac": "flac"
        case "audio/mp4", "audio/m4a", "audio/x-m4a": "m4a"
        case "audio/aac": "aac"
        case "audio/ogg", "audio/vorbis": "ogg"
        case "audio/wav", "audio/x-wav": "wav"
        default: "mp3"
        }
    }

    // MARK: - Test Helpers

    /// Exposes hasMoovAtom for unit tests via @testable import.
    nonisolated static func testHasMoovAtom(at url: URL) -> Bool {
        hasMoovAtom(at: url)
    }
}
