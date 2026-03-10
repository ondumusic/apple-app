import Foundation

@Observable
final class DownloadService: NSObject, URLSessionDownloadDelegate {
    // MARK: - Public state

    /// Active downloads (in-flight): track ID → metadata
    var activeDownloads: [UUID: DownloadState] = [:]

    /// Ordered list of active download track IDs (for stable UI ordering)
    var activeDownloadOrder: [UUID] = []

    /// Downloads waiting to start (token not yet resolved)
    var pendingQueue: [DownloadInfo] = []

    /// Whether all downloads are paused
    var isPaused: Bool = false

    /// Progress snapshot updated on a timer (~2x/sec) for UI display only
    var progressSnapshot: [UUID: Double] = [:]

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
    }

    // MARK: - Private

    @ObservationIgnored private let musicLibrary: MusicLibrary
    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let tokenManager = PlayTokenManager()

    @ObservationIgnored private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.musicbox.downloads.delegate"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    @ObservationIgnored private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.musicbox.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    /// Maps URLSession task identifier → download info (for UI state management)
    @ObservationIgnored private var taskDownloads: [Int: DownloadInfo] = [:]
    /// Maps track ID → URLSession task identifier
    @ObservationIgnored private var trackIdToTaskId: [UUID: Int] = [:]
    /// Maps track ID → active URLSessionDownloadTask (for pause support)
    @ObservationIgnored private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Stores info for paused downloads: track ID → (info + resolved URL for restart)
    @ObservationIgnored private var pausedDownloads: [UUID: (info: DownloadInfo, resolvedURL: URL)] = [:]
    /// Downloads that failed due to expired token, to retry when app is active
    @ObservationIgnored private var retryQueue: [DownloadInfo] = []
    /// Raw progress values — not observable, updated on every delegate callback
    @ObservationIgnored private var progressValues: [UUID: Double] = [:]
    /// Timer that batches progress into the observable snapshot
    @ObservationIgnored private var progressTimer: Timer?
    /// Number of in-flight downloads — incremented synchronously, so concurrent calls
    /// to startNextIfNeeded can't exceed the limit.
    @ObservationIgnored private var inFlightCount: Int = 0
    /// Whether we're currently resolving tokens and starting tasks
    @ObservationIgnored private var isStartingNext: Bool = false

    // MARK: - Paths

    nonisolated private static var downloadsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MusicBox/Downloads", isDirectory: true)
    }

    nonisolated private static var pendingDirectory: URL {
        downloadsDirectory.appendingPathComponent(".pending", isDirectory: true)
    }

    // MARK: - Init

    init(api: APIService, musicLibrary: MusicLibrary, settings: SettingsStore) {
        self.api = api
        self.musicLibrary = musicLibrary
        self.settings = settings
        super.init()
        _ = downloadSession
        processPendingCompletions()
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

        if let task = activeTasks.removeValue(forKey: trackId) {
            let taskId = task.taskIdentifier
            task.cancel()
            taskDownloads.removeValue(forKey: taskId)
            trackIdToTaskId.removeValue(forKey: trackId)
            inFlightCount -= 1
        }
        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        progressValues.removeValue(forKey: trackId)
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    func pauseDownload(trackId: UUID) {
        guard let task = activeTasks.removeValue(forKey: trackId),
              let info = taskDownloads[task.taskIdentifier] else { return }

        let taskId = task.taskIdentifier
        let resolvedURL = task.originalRequest?.url
        task.cancel()

        taskDownloads.removeValue(forKey: taskId)
        trackIdToTaskId.removeValue(forKey: trackId)
        inFlightCount -= 1

        if let resolvedURL {
            pausedDownloads[trackId] = (info: info, resolvedURL: resolvedURL)
        }
        activeDownloads[trackId]?.isPaused = true
    }

    func resumeDownload(trackId: UUID) {
        guard let paused = pausedDownloads.removeValue(forKey: trackId) else { return }

        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }

        if inFlightCount < settings.maxConcurrentDownloads {
            startTask(info: paused.info, resolvedURL: paused.resolvedURL)
        } else {
            pendingQueue.insert(paused.info, at: 0)
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
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        taskDownloads.removeAll()
        trackIdToTaskId.removeAll()
        activeDownloads.removeAll()
        activeDownloadOrder.removeAll()
        pendingQueue.removeAll()
        pausedDownloads.removeAll()
        retryQueue.removeAll()
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
        !activeDownloads.isEmpty || !pendingQueue.isEmpty || !retryQueue.isEmpty
    }

    // MARK: - Internal queue management

    /// Resolves token and starts tasks up to the concurrency limit.
    private func startNextIfNeeded() {
        guard !isPaused, !isStartingNext else { return }
        guard !pendingQueue.isEmpty, inFlightCount < settings.maxConcurrentDownloads else { return }

        isStartingNext = true

        var toStart: [DownloadInfo] = []
        while !pendingQueue.isEmpty, (inFlightCount + toStart.count) < settings.maxConcurrentDownloads {
            let next = pendingQueue.removeFirst()
            if musicLibrary.isDownloaded(trackId: next.track.id) { continue }
            toStart.append(next)
        }

        guard !toStart.isEmpty else {
            isStartingNext = false
            return
        }

        Task { @MainActor in
            defer { isStartingNext = false }
            do {
                let token = try await tokenManager.validToken(using: api)
                for info in toStart {
                    guard let url = self.resolveURL(for: info.track, token: token) else { continue }
                    self.startTask(info: info, resolvedURL: url)
                }
            } catch {
                print("DownloadService: failed to get token: \(error)")
                self.pendingQueue.insert(contentsOf: toStart, at: 0)
            }
        }
    }

    /// Creates and resumes a URLSession download task.
    private func startTask(info: DownloadInfo, resolvedURL: URL) {
        inFlightCount += 1

        activeDownloads[info.track.id] = DownloadState(
            trackName: info.track.name,
            artistName: info.artist.name,
            albumId: info.album.id
        )
        activeDownloadOrder.append(info.track.id)
        progressValues[info.track.id] = 0
        startProgressTimerIfNeeded()

        let task = downloadSession.downloadTask(with: resolvedURL)

        // Store metadata in taskDescription — survives app termination + relaunch
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

    private func resolveURL(for track: Track, token: String) -> URL? {
        guard let streamURL = URL(string: track.streamUrl),
              var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems
        return components.url
    }

    private func cleanupTask(trackId: UUID, taskId: Int) {
        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        trackIdToTaskId.removeValue(forKey: trackId)
        activeTasks.removeValue(forKey: trackId)
        progressValues.removeValue(forKey: trackId)
        taskDownloads.removeValue(forKey: taskId)
        inFlightCount -= 1
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

    /// Retries downloads that failed due to expired tokens. Call when app becomes active.
    func retryFailedDownloads() {
        processPendingCompletions()
        startNextIfNeeded()

        guard !retryQueue.isEmpty else { return }
        let toRetry = retryQueue
        retryQueue.removeAll()
        Task { @MainActor in
            await tokenManager.invalidate()
            for info in toRetry {
                if !musicLibrary.isDownloaded(trackId: info.track.id) {
                    pendingQueue.append(info)
                }
            }
            startNextIfNeeded()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            return
        }

        // Decode metadata from taskDescription — works even after app relaunch
        guard let descriptionData = downloadTask.taskDescription?.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(TaskMetadata.self, from: descriptionData) else {
            // Fallback: move to tmp (will be cleaned up)
            print("DownloadService: no metadata for task \(downloadTask.taskIdentifier), skipping")
            return
        }

        // Move file directly to final location (nonisolated — runs in background)
        let relativePath = saveDownloadedFile(metadata: metadata, tempLocation: location)

        if let relativePath {
            // Write pending completion for SwiftData update on foreground
            writePendingCompletion(trackId: metadata.trackId, relativePath: relativePath)
        }

        // Update UI state on MainActor (may not execute if suspended — that's OK)
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            if let relativePath {
                self.musicLibrary.markDownloaded(trackId: metadata.trackId, relativePath: relativePath)
                self.removePendingCompletion(trackId: metadata.trackId)
            }
            self.cleanupTask(trackId: metadata.trackId, taskId: taskId)
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

        Task { @MainActor in
            guard let info = taskDownloads[taskId] else { return }

            if let statusCode, (statusCode == 401 || statusCode == 403) {
                cleanupTask(trackId: info.track.id, taskId: taskId)
                var retryInfo = info
                retryInfo.retryCount += 1
                if retryInfo.retryCount <= 3 {
                    print("DownloadService: token expired for \(info.track.name), queuing retry (\(retryInfo.retryCount)/3)")
                    retryQueue.append(retryInfo)
                } else {
                    print("DownloadService: giving up on \(info.track.name) after 3 retries")
                }
                return
            }

            guard let error else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            print("DownloadService: download failed for \(info.track.name): \(error)")
            cleanupTask(trackId: info.track.id, taskId: taskId)
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

    /// Moves downloaded file directly to its final path. Runs on delegate queue (nonisolated).
    nonisolated private func saveDownloadedFile(metadata: TaskMetadata, tempLocation: URL) -> String? {
        let fm = FileManager.default
        let dir = Self.downloadsDirectory
            .appendingPathComponent(metadata.artistId.uuidString, isDirectory: true)
            .appendingPathComponent(metadata.albumId.uuidString, isDirectory: true)

        let ext = extensionFromMimetype(metadata.mimetype)
        let destURL = dir.appendingPathComponent("\(metadata.trackId.uuidString).\(ext)")
        let relativePath = "MusicBox/Downloads/\(metadata.artistId.uuidString)/\(metadata.albumId.uuidString)/\(metadata.trackId.uuidString).\(ext)"

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: tempLocation, to: destURL)
            return relativePath
        } catch {
            print("DownloadService: failed to save file for \(metadata.trackName): \(error)")
            return nil
        }
    }

    /// Writes a pending completion record to disk. If the app is suspended before
    /// SwiftData can be updated, this record is processed on next foreground.
    nonisolated private func writePendingCompletion(trackId: UUID, relativePath: String) {
        let fm = FileManager.default
        let dir = Self.pendingDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let record = PendingCompletion(trackId: trackId, relativePath: relativePath)
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
                musicLibrary.markDownloaded(trackId: record.trackId, relativePath: record.relativePath)
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
}
