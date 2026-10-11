import Foundation

/// Caches streamed audio files on disk with LRU eviction.
/// Priority: OfflineStore (downloads) > PlaybackCache > stream from server.
@Observable
final class PlaybackCache {
    private(set) var currentSize: Int64 = 0

    @ObservationIgnored private let cacheDir: URL
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let fileManager = FileManager.default
    /// Maps trackId -> relative filename. Ordered by last access (most recent last).
    @ObservationIgnored private var entries: [CacheEntry] = []
    @ObservationIgnored private var metadataDirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    nonisolated struct CacheEntry: Codable, Sendable {
        var trackId: UUID
        var filename: String
        var size: Int64
        var lastAccessed: Date
    }

    init(settings: SettingsStore) {
        self.settings = settings
        let appSupport =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.cacheDir = appSupport.appendingPathComponent("Ondu/PlaybackCache", isDirectory: true)
        self.metadataURL = cacheDir.appendingPathComponent(".cache-metadata.json")

        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    /// Test-only initializer with custom cache directory.
    init(settings: SettingsStore, cacheDir: URL) {
        self.settings = settings
        self.cacheDir = cacheDir
        self.metadataURL = cacheDir.appendingPathComponent(".cache-metadata.json")

        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    // MARK: - Public

    /// Returns the local file URL if the track is cached, updating last-accessed time.
    func cachedURL(for trackId: UUID) -> URL? {
        guard let idx = entries.firstIndex(where: { $0.trackId == trackId }) else { return nil }
        let url = cacheDir.appendingPathComponent(entries[idx].filename)
        guard fileManager.fileExists(atPath: url.path) else {
            // File disappeared — remove entry
            entries.remove(at: idx)
            recalculateSize()
            saveMetadata()
            return nil
        }
        // Update last accessed (move to end = most recently used)
        entries[idx].lastAccessed = Date()
        let entry = entries.remove(at: idx)
        entries.append(entry)
        metadataDirty = true
        scheduleDeferredSave()
        return url
    }

    /// Downloads the stream URL to a local file and returns the cached file URL.
    /// Returns nil if caching fails (playback should fall back to streaming).
    func cacheTrack(trackId: UUID, from streamURL: URL, sessionToken: String? = nil) async -> URL? {
        // Already cached?
        if let existing = cachedURL(for: trackId) { return existing }

        do {
            let (tempURL, response): (URL, URLResponse)
            if let sessionToken {
                var request = URLRequest(url: streamURL)
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
                (tempURL, response) = try await URLSession.shared.download(for: request)
            } else {
                (tempURL, response) = try await URLSession.shared.download(from: streamURL)
            }

            // Determine file extension from MIME type or URL
            let ext = fileExtension(from: response, url: streamURL)
            let filename = "\(trackId.uuidString).\(ext)"
            let destURL = cacheDir.appendingPathComponent(filename)

            // Remove existing file if any
            try? fileManager.removeItem(at: destURL)
            try fileManager.moveItem(at: tempURL, to: destURL)

            let fileSize = (try? fileManager.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0

            let entry = CacheEntry(trackId: trackId, filename: filename, size: fileSize, lastAccessed: Date())
            await MainActor.run {
                self.entries.append(entry)
                self.currentSize += fileSize
                self.evictIfNeeded()
                self.saveMetadata()
            }

            return destURL
        } catch {
            #if DEBUG
            print("PlaybackCache: failed to cache track \(trackId): \(error)")
            #endif
            return nil
        }
    }

    /// Total size formatted for display.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: currentSize, countStyle: .file)
    }

    /// Removes all cached files.
    func clearCache() {
        for entry in entries {
            let url = cacheDir.appendingPathComponent(entry.filename)
            try? fileManager.removeItem(at: url)
        }
        entries.removeAll()
        currentSize = 0
        saveMetadata()
    }

    var trackCount: Int { entries.count }

    // MARK: - Private

    private func evictIfNeeded() {
        let limit = settings.playbackCacheLimit
        guard limit > 0 else { return }  // 0 = unlimited

        // Evict least recently used entries until under limit
        while currentSize > limit && !entries.isEmpty {
            let entry = entries.removeFirst()
            let url = cacheDir.appendingPathComponent(entry.filename)
            try? fileManager.removeItem(at: url)
            currentSize -= entry.size
        }
        if currentSize < 0 { currentSize = 0 }
    }

    private func recalculateSize() {
        currentSize = entries.reduce(0) { $0 + $1.size }
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
            let loaded = try? JSONDecoder().decode([CacheEntry].self, from: data)
        else {
            recalculateSize()
            return
        }
        // Validate files still exist
        entries = loaded.filter { entry in
            fileManager.fileExists(atPath: cacheDir.appendingPathComponent(entry.filename).path)
        }
        // Sort by lastAccessed (LRU order: oldest first)
        entries.sort { $0.lastAccessed < $1.lastAccessed }
        recalculateSize()
    }

    private func saveMetadata() {
        metadataDirty = false
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    /// Save after a short delay — coalesces rapid access updates.
    private func scheduleDeferredSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.flushMetadataIfNeeded()
        }
    }

    func flushMetadataIfNeeded() {
        guard metadataDirty else { return }
        saveMetadata()
    }

    private func fileExtension(from response: URLResponse, url: URL) -> String {
        if let mimeType = response.mimeType {
            let ext = AudioFormat.fileExtension(for: mimeType, fallback: "")
            if !ext.isEmpty { return ext }
        }
        let pathExt = url.pathExtension
        return pathExt.isEmpty ? "audio" : pathExt
    }
}
