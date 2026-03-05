import Foundation

@Observable
final class DownloadService: NSObject, URLSessionDownloadDelegate {
    // MARK: - Public state

    /// Active downloads: track ID → current progress and metadata
    var activeDownloads: [UUID: DownloadState] = [:]

    /// Queued downloads waiting to start
    var pendingQueue: [DownloadInfo] = []

    /// Whether all downloads are paused
    var isPaused: Bool = false

    nonisolated struct DownloadState: Sendable {
        let trackName: String
        let artistName: String
        var progress: Double
        var isPaused: Bool = false
    }

    nonisolated struct DownloadInfo: Sendable {
        let track: Track
        let album: Album
        let artist: Artist
    }

    // MARK: - Private

    @ObservationIgnored private let offlineStore: OfflineStore
    @ObservationIgnored private let api: APIService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let tokenManager = PlayTokenManager()

    @ObservationIgnored private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    /// Maps URLSession task identifier → download info
    @ObservationIgnored private var taskDownloads: [Int: DownloadInfo] = [:]
    /// Maps track ID → URLSession task identifier
    @ObservationIgnored private var trackIdToTaskId: [UUID: Int] = [:]
    /// Maps track ID → active URLSessionDownloadTask (for pause support)
    @ObservationIgnored private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Stores info for paused downloads: track ID → DownloadInfo
    @ObservationIgnored private var pausedDownloads: [UUID: DownloadInfo] = [:]

    // MARK: - Init

    init(api: APIService, offlineStore: OfflineStore, settings: SettingsStore) {
        self.api = api
        self.offlineStore = offlineStore
        self.settings = settings
        super.init()
        _ = downloadSession
    }

    // MARK: - Public API

    func download(track: Track, album: Album, artist: Artist) {
        guard !offlineStore.isDownloaded(trackId: track.id),
              !isDownloading(trackId: track.id),
              !isQueued(trackId: track.id) else { return }

        let info = DownloadInfo(track: track, album: album, artist: artist)

        if !isPaused && activeDownloads.count < settings.maxConcurrentDownloads {
            startDownload(info)
        } else {
            pendingQueue.append(info)
        }
    }

    func download(album: Album, artist: Artist) {
        guard let tracks = album.tracks else { return }
        for track in tracks {
            download(track: track, album: album, artist: artist)
        }
    }

    // MARK: - Per-track controls

    func cancelDownload(trackId: UUID) {
        // Remove from pending queue
        pendingQueue.removeAll { $0.track.id == trackId }

        // Remove from paused
        pausedDownloads.removeValue(forKey: trackId)

        // Cancel active download using stored task reference
        if let task = activeTasks.removeValue(forKey: trackId) {
            let taskId = task.taskIdentifier
            task.cancel()
            taskDownloads.removeValue(forKey: taskId)
            trackIdToTaskId.removeValue(forKey: trackId)
        }
        activeDownloads.removeValue(forKey: trackId)
        startNextIfNeeded()
    }

    func pauseDownload(trackId: UUID) {
        guard let task = activeTasks.removeValue(forKey: trackId),
              let info = taskDownloads[task.taskIdentifier] else { return }

        let taskId = task.taskIdentifier
        task.cancel()

        // Clean up active tracking
        taskDownloads.removeValue(forKey: taskId)
        trackIdToTaskId.removeValue(forKey: trackId)

        // Store info for later restart and mark paused in UI
        pausedDownloads[trackId] = info
        activeDownloads[trackId]?.isPaused = true
    }

    func resumeDownload(trackId: UUID) {
        guard let info = pausedDownloads.removeValue(forKey: trackId) else { return }

        // Remove old paused state and start fresh
        activeDownloads.removeValue(forKey: trackId)
        startDownload(info)
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
        pendingQueue.removeAll()
        pausedDownloads.removeAll()
    }

    // MARK: - Query

    func isDownloading(trackId: UUID) -> Bool {
        activeDownloads[trackId] != nil
    }

    func isQueued(trackId: UUID) -> Bool {
        pendingQueue.contains { $0.track.id == trackId }
    }

    var hasActivity: Bool {
        !activeDownloads.isEmpty || !pendingQueue.isEmpty
    }

    // MARK: - Internal queue management

    private func startDownload(_ info: DownloadInfo) {
        activeDownloads[info.track.id] = DownloadState(
            trackName: info.track.name,
            artistName: info.artist.name,
            progress: 0
        )

        Task { @MainActor in
            do {
                let url = try await tokenManager.resolvedStreamURL(for: info.track, using: api)
                let task = downloadSession.downloadTask(with: url)
                taskDownloads[task.taskIdentifier] = info
                trackIdToTaskId[info.track.id] = task.taskIdentifier
                activeTasks[info.track.id] = task
                task.resume()
            } catch {
                print("DownloadService: failed to resolve URL for \(info.track.name): \(error)")
                activeDownloads.removeValue(forKey: info.track.id)
                startNextIfNeeded()
            }
        }
    }

    private func startNextIfNeeded() {
        guard !isPaused else { return }
        while activeDownloads.count < settings.maxConcurrentDownloads, !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            if offlineStore.isDownloaded(trackId: next.track.id) { continue }
            startDownload(next)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        MainActor.assumeIsolated {
            handleDownloadComplete(taskId: downloadTask.taskIdentifier, location: location)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            guard let info = taskDownloads[downloadTask.taskIdentifier] else { return }
            let progress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0
            activeDownloads[info.track.id]?.progress = progress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            guard let error else { return }
            // Ignore cancellation errors from pause (resume data handled separately)
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard let info = taskDownloads[task.taskIdentifier] else { return }
            print("DownloadService: download failed for \(info.track.name): \(error)")
            activeDownloads.removeValue(forKey: info.track.id)
            trackIdToTaskId.removeValue(forKey: info.track.id)
            activeTasks.removeValue(forKey: info.track.id)
            taskDownloads.removeValue(forKey: task.taskIdentifier)
            startNextIfNeeded()
        }
    }

    // MARK: - Private

    private func handleDownloadComplete(taskId: Int, location: URL) {
        guard let info = taskDownloads[taskId] else { return }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            .appendingPathComponent(info.artist.id.uuidString, isDirectory: true)
            .appendingPathComponent(info.album.id.uuidString, isDirectory: true)

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let ext = extensionFromMimetype(info.track.mimetype)
            let destURL = dir.appendingPathComponent("\(info.track.id.uuidString).\(ext)")

            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: location, to: destURL)

            let downloadedArtist = offlineStore.ensureArtist(from: info.artist)
            let downloadedAlbum = offlineStore.ensureAlbum(from: info.album, artist: downloadedArtist)
            offlineStore.insertTrack(info.track, localFileURL: destURL, album: downloadedAlbum)
        } catch {
            print("DownloadService: failed to save \(info.track.name): \(error)")
        }

        activeDownloads.removeValue(forKey: info.track.id)
        trackIdToTaskId.removeValue(forKey: info.track.id)
        activeTasks.removeValue(forKey: info.track.id)
        taskDownloads.removeValue(forKey: taskId)
        startNextIfNeeded()
    }

    private func extensionFromMimetype(_ mimetype: String) -> String {
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
