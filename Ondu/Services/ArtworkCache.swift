import Foundation
import Nuke

/// Album covers and artist photos on disk, through Nuke's data cache.
nonisolated enum ArtworkCache {
    /// Room for a whole library's artwork. Nuke's default of 150 MB was smaller than a large
    /// library, so preloading after a sync evicted covers as fast as it fetched them, and
    /// browsing offline — downloaded albums included — showed placeholders. A cover at the
    /// size Ondu uses is 50–120 KB, and each rendition it is drawn at adds a resized copy,
    /// so this holds a library of several thousand albums; the space is only taken as
    /// artwork arrives.
    static let sizeLimit = 2 * 1024 * 1024 * 1024

    /// Beside the downloads rather than in Caches: covers someone chose to preload are
    /// library data for listening offline, and Caches is what the system clears when it
    /// wants the room back.
    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Ondu/Artwork")
    }

    static func pipelineConfiguration() -> ImagePipeline.Configuration {
        var configuration = ImagePipeline.Configuration.withDataCache(sizeLimit: sizeLimit)
        if var directory, let cache = try? DataCache(path: directory) {
            cache.sizeLimit = sizeLimit
            // Re-downloadable, so it has no business in a backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            configuration.dataCache = cache
        }
        // Resized renditions on disk as well as the original, so a cover coming back
        // from disk is a cheap decode at the size it is drawn, not the original decoded
        // and resized again every time.
        configuration.dataCachePolicy = .storeAll
        removeFormerCache()
        return configuration
    }

    /// Where the artwork lived before it moved beside the downloads.
    private static func removeFormerCache() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("com.github.kean.Nuke.DataCache"))
    }

    private static var dataCache: DataCache? {
        ImagePipeline.shared.configuration.dataCache as? DataCache
    }

    /// Reads the disk, so it runs off the main actor.
    static func size() async -> Int64 {
        await Task.detached(priority: .utility) {
            Int64(dataCache?.totalSize ?? 0)
        }.value
    }

    static func clear() {
        ImagePipeline.shared.cache.removeAll()
    }
}
