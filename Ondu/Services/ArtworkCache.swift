import Foundation
import Nuke

/// Album covers and artist photos on disk, through Nuke's data cache.
nonisolated enum ArtworkCache {
    /// Room for a whole library's artwork. Nuke's default of 150 MB was smaller than a large
    /// library, so preloading after a sync evicted covers as fast as it fetched them, and
    /// browsing offline — downloaded albums included — showed placeholders. A cover at the
    /// size Ondu uses is 50–120 KB, so this holds ten thousand albums or so; the space is
    /// only taken as artwork arrives.
    static let sizeLimit = 1024 * 1024 * 1024

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
