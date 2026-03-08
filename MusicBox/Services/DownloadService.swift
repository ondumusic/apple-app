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

    // MARK: - Private

    @ObservationIgnored private let offlineStore: OfflineStore
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

    /// Maps URLSession task identifier → download info
    @ObservationIgnored private var taskDownloads: [Int: DownloadInfo] = [:]
    /// Maps track ID → URLSession task identifier
    @ObservationIgnored private var trackIdToTaskId: [UUID: Int] = [:]
    /// Maps track ID → active URLSessionDownloadTask (for pause support)
    @ObservationIgnored private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Stores info for paused downloads: track ID → DownloadInfo
    @ObservationIgnored private var pausedDownloads: [UUID: DownloadInfo] = [:]
    /// Raw progress values — not observable, updated on every delegate callback
    @ObservationIgnored private var progressValues: [UUID: Double] = [:]
    /// Timer that batches progress into the observable snapshot
    @ObservationIgnored private var progressTimer: Timer?

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

    func downloadAll(library: MusicLibrary) {
        let artists = library.allArtists()
        for artist in artists {
            let albums = library.albumsWithTracksForArtist(artist.id)
            for album in albums {
                download(album: album, artist: artist)
            }
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
        progressValues.removeValue(forKey: trackId)
        stopProgressTimerIfIdle()
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

    private func startDownload(_ info: DownloadInfo) {
        activeDownloads[info.track.id] = DownloadState(
            trackName: info.track.name,
            artistName: info.artist.name,
            albumId: info.album.id
        )
        progressValues[info.track.id] = 0
        startProgressTimerIfNeeded()

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
        // Must move file immediately — location is deleted after this method returns.
        let taskId = downloadTask.taskIdentifier
        let savedURL = moveDownloadToFinalLocation(taskId: taskId, tempLocation: location)
        Task { @MainActor in
            finalizeDownload(taskId: taskId, savedURL: savedURL)
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
        guard let error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in
            guard let info = taskDownloads[taskId] else { return }
            print("DownloadService: download failed for \(info.track.name): \(error)")
            activeDownloads.removeValue(forKey: info.track.id)
            trackIdToTaskId.removeValue(forKey: info.track.id)
            activeTasks.removeValue(forKey: info.track.id)
            taskDownloads.removeValue(forKey: taskId)
            startNextIfNeeded()
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            #if os(iOS)
            let handler = BackgroundSessionDelegate.pendingCompletionHandler
            BackgroundSessionDelegate.pendingCompletionHandler = nil
            handler?()
            #endif
        }
    }

    // MARK: - Private

    /// Moves the downloaded file to its final location. Called on the delegate queue (background thread)
    /// because the temp file at `location` is deleted after `didFinishDownloadingTo` returns.
    nonisolated private func moveDownloadToFinalLocation(taskId: Int, tempLocation: URL) -> URL? {
        // Read taskDownloads directly — safe because delegateQueue is serial
        // and taskDownloads is only mutated on MainActor before the task starts.
        // We capture the info we need synchronously.
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tempDest = appSupport
            .appendingPathComponent("MusicBox/Downloads", isDirectory: true)
            .appendingPathComponent("tmp-\(taskId)")
        do {
            try fm.createDirectory(
                at: appSupport.appendingPathComponent("MusicBox/Downloads", isDirectory: true),
                withIntermediateDirectories: true)
            if fm.fileExists(atPath: tempDest.path) {
                try fm.removeItem(at: tempDest)
            }
            try fm.moveItem(at: tempLocation, to: tempDest)
            return tempDest
        } catch {
            print("DownloadService: failed to save temp file: \(error)")
            return nil
        }
    }

    /// Finalizes the download on the main actor: moves to final path, inserts into store.
    private func finalizeDownload(taskId: Int, savedURL: URL?) {
        guard let info = taskDownloads[taskId] else { return }

        if let savedURL {
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
                try fm.moveItem(at: savedURL, to: destURL)

                print("DownloadService: saved \(info.track.name) to \(destURL.path)")
                print("DownloadService: albumArtistId=\(info.artist.id), trackArtistId=\(info.track.artistId)")
                let downloadedArtist = offlineStore.ensureArtist(from: info.artist)
                let downloadedAlbum = offlineStore.ensureAlbum(from: info.album, artist: downloadedArtist)
                offlineStore.insertTrack(info.track, localFileURL: destURL, album: downloadedAlbum)
            } catch {
                print("DownloadService: failed to save \(info.track.name): \(error)")
                try? fm.removeItem(at: savedURL)
            }
        }

        activeDownloads.removeValue(forKey: info.track.id)
        trackIdToTaskId.removeValue(forKey: info.track.id)
        activeTasks.removeValue(forKey: info.track.id)
        progressValues.removeValue(forKey: info.track.id)
        taskDownloads.removeValue(forKey: taskId)
        stopProgressTimerIfIdle()
        startNextIfNeeded()
    }

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
