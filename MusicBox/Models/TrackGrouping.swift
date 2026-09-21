import Foundation

nonisolated enum TrackGrouping {
    /// Flat track index → the label of a divider row that belongs above it.
    ///
    /// Only albums that actually span discs get them: numbering restarts at 1 on each
    /// disc, which reads as a duplicate row without something in between.
    static func discLabels(for tracks: [Track]) -> [Int: String] {
        guard Set(tracks.map(\.disc)).count > 1 else { return [:] }
        var labels: [Int: String] = [:]
        var previous: Int?
        for (index, track) in tracks.enumerated() where track.disc != previous {
            labels[index] = String(localized: "Disc \(track.disc)")
            previous = track.disc
        }
        return labels
    }
}
