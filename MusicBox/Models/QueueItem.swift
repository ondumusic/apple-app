import Foundation

nonisolated struct QueueItem: Identifiable, Sendable {
    var id = UUID()
    var track: Track
    var playbackURL: URL?
}
