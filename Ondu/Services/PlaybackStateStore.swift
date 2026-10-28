import Foundation

/// The queue as it stood — changes only when the user changes it, so it's written on mutation.
/// Tracks are stored as ids and re-resolved against `MusicLibrary` on restore, so a queue picks
/// up whatever metadata and download state sync has landed since.
nonisolated struct PlaybackState: Codable, Sendable, Equatable {
    var trackIds: [UUID]
    var currentIndex: Int
    var shuffledIndices: [Int]?
    /// Optional so snapshots written before this existed still decode.
    var isUserModified: Bool?
}

/// Where playback had got to. Carries the track id so a stale position — written moments before
/// an unclean kill, against a queue that has since moved on — can be recognised and dropped.
nonisolated struct PlaybackPosition: Sendable, Equatable {
    var trackId: UUID
    var elapsed: Double
}

/// Splits playback state by how often it changes: the queue lands in a JSON file on mutation,
/// the position in `UserDefaults` every few seconds. Rewriting the whole queue that often would
/// mean tens of KB of file I/O per minute for a large queue, to record two numbers.
final class PlaybackStateStore {
    private let fileURL: URL
    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    /// The most recent queued write, so the next one can chain after it.
    private var pendingWrite: Task<Void, Never>?

    private enum Keys {
        static let positionTrackId = "playback.positionTrackId"
        static let positionElapsed = "playback.positionElapsed"
    }

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return appSupport.appendingPathComponent("Ondu/.playback-state.json")
    }

    init() {
        self.fileURL = Self.defaultFileURL()
        self.defaults = .standard
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// Test-only initializer with a custom file location and defaults suite.
    init(fileURL: URL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    // MARK: - Queue

    func load() -> PlaybackState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PlaybackState.self, from: data)
    }

    /// Encodes on the caller, writes off it.
    ///
    /// An atomic write is a temp file, a write and a rename — real syscalls, and this is
    /// called from interactive gestures like reordering the queue, where doing that on
    /// the main thread is felt. Writes chain off each other so they still land in the
    /// order they were made.
    func save(_ state: PlaybackState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = fileURL
        let previous = pendingWrite
        pendingWrite = Task.detached(priority: .utility) {
            await previous?.value
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Lets a caller wait for queued writes — tests, and anywhere that needs the file on
    /// disk before it reads it back.
    func flush() async {
        await pendingWrite?.value
    }

    // MARK: - Position

    func loadPosition() -> PlaybackPosition? {
        guard let raw = defaults.string(forKey: Keys.positionTrackId),
            let trackId = UUID(uuidString: raw)
        else { return nil }
        return PlaybackPosition(trackId: trackId, elapsed: defaults.double(forKey: Keys.positionElapsed))
    }

    func savePosition(_ position: PlaybackPosition) {
        defaults.set(position.trackId.uuidString, forKey: Keys.positionTrackId)
        defaults.set(position.elapsed, forKey: Keys.positionElapsed)
    }

    // MARK: - Lifecycle

    /// Chained after any queued save so a snapshot written moments earlier cannot land
    /// after the clear and bring the queue back on the next launch.
    func clear() {
        let url = fileURL
        let defaults = defaults
        let previous = pendingWrite
        pendingWrite = Task.detached(priority: .utility) {
            await previous?.value
            try? FileManager.default.removeItem(at: url)
            defaults.removeObject(forKey: Keys.positionTrackId)
            defaults.removeObject(forKey: Keys.positionElapsed)
        }
    }

    /// Wipes both halves without a live player — used on logout, where the player is torn down.
    static func clearPersisted() {
        try? FileManager.default.removeItem(at: defaultFileURL())
        UserDefaults.standard.removeObject(forKey: Keys.positionTrackId)
        UserDefaults.standard.removeObject(forKey: Keys.positionElapsed)
    }
}
