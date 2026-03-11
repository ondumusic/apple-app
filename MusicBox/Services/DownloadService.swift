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
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    /// Foreground session — faster (no IPC overhead), used while app is active
    @ObservationIgnored private lazy var foregroundSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = sessionHeaders
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
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
    /// Stores info for paused downloads
    @ObservationIgnored private var pausedDownloads: [UUID: DownloadInfo] = [:]
    /// Raw progress values — not observable, updated on every delegate callback
    @ObservationIgnored private var progressValues: [UUID: Double] = [:]
    /// Timer that batches progress into the observable snapshot
    @ObservationIgnored private var progressTimer: Timer?
    /// Number of in-flight downloads — incremented synchronously, so concurrent calls
    /// to startNextIfNeeded can't exceed the limit.
    @ObservationIgnored private var inFlightCount: Int = 0

    // MARK: - Paths

    nonisolated private static var downloadsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MusicBox/Downloads", isDirectory: true)
    }

    nonisolated private static var pendingDirectory: URL {
        downloadsDirectory.appendingPathComponent(".pending", isDirectory: true)
    }

    // MARK: - Init

    init(sessionToken: String, musicLibrary: MusicLibrary, settings: SettingsStore) {
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
        !activeDownloads.isEmpty || !pendingQueue.isEmpty
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
        guard var url = URL(string: info.track.streamUrl) else { return }

        // Apply transcode settings if not original quality
        let quality = settings.downloadQuality
        if quality != .original,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "transcode", value: "1"))
            queryItems.append(URLQueryItem(name: "preset", value: quality.rawValue))
            components.queryItems = queryItems
            url = components.url ?? url
        }

        inFlightCount += 1

        activeDownloads[info.track.id] = DownloadState(
            trackName: info.track.name,
            artistName: info.artist.name,
            albumId: info.album.id
        )
        activeDownloadOrder.append(info.track.id)
        progressValues[info.track.id] = 0
        startProgressTimerIfNeeded()

        let session = isInForeground ? foregroundSession : backgroundSession
        print("DownloadService: \(info.track.name) using \(isInForeground ? "foreground" : "background") session")
        let task = session.downloadTask(with: url)

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

    private func cleanupTask(trackId: UUID, taskId: Int) {
        // Guard: only clean up if this task is still tracked (prevents double-cleanup
        // when migrateToBackground already cleaned up a cancelled task)
        guard taskDownloads.removeValue(forKey: taskId) != nil else { return }
        activeDownloads.removeValue(forKey: trackId)
        activeDownloadOrder.removeAll { $0 == trackId }
        trackIdToTaskId.removeValue(forKey: trackId)
        activeTasks.removeValue(forKey: trackId)
        progressValues.removeValue(forKey: trackId)
        inFlightCount -= 1
        stopProgressTimerIfIdle()
        startNextIfNeeded()
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
        #else
        let backgroundName = NSApplication.willResignActiveNotification
        #endif

        NotificationCenter.default.addObserver(
            forName: backgroundName, object: nil, queue: .main
        ) { [weak self] _ in self?.migrateToBackground() }
    }

    /// App is going to background — move in-flight foreground tasks to background session.
    private func migrateToBackground() {
        isInForeground = false
        let inflight = activeTasks
        guard !inflight.isEmpty else { return }

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
        let saved = saveDownloadedFile(metadata: metadata, tempLocation: location)

        if let saved {
            // Write pending completion for SwiftData update on foreground
            writePendingCompletion(trackId: metadata.trackId, relativePath: saved.path, downloadedFileSize: saved.size)
        }

        // Update UI state on MainActor (may not execute if suspended — that's OK)
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            if let saved {
                self.musicLibrary.markDownloaded(trackId: metadata.trackId, relativePath: saved.path, downloadedFileSize: saved.size)
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

            if let statusCode, !(200...299).contains(statusCode) {
                print("DownloadService: HTTP \(statusCode) for \(info.track.name)")
                cleanupTask(trackId: info.track.id, taskId: taskId)
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

    /// Moves downloaded file directly to its final path. Returns (relativePath, fileSize) or nil.
    nonisolated private func saveDownloadedFile(metadata: TaskMetadata, tempLocation: URL) -> (path: String, size: Int64)? {
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
            let size = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
            return (relativePath, size)
        } catch {
            print("DownloadService: failed to save file for \(metadata.trackName): \(error)")
            return nil
        }
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
}
