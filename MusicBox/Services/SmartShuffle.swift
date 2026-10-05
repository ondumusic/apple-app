import Foundation

/// Fisher-Yates alone produces same-artist runs that listeners read as "not random".
/// Instead, each artist's tracks are placed at even intervals across the whole queue
/// (with a random offset per artist and jitter per track so no pattern shows), and an
/// artist's own tracks are ordered the same way by album before placement.
enum SmartShuffle {
    static func shuffledIndices(for items: [QueueItem]) -> [Int] {
        var rng = SystemRandomNumberGenerator()
        return shuffledIndices(for: items, using: &rng)
    }

    static func shuffledIndices(for items: [QueueItem], using rng: inout some RandomNumberGenerator) -> [Int] {
        let all = Array(items.indices)
        let byArtist = groups(of: all) { items[$0].track.albumArtistId }
        guard byArtist.count > 1 else { return spreadByAlbum(all, items: items, using: &rng) }

        var placed: [(position: Double, index: Int)] = []
        placed.reserveCapacity(all.count)
        for artist in byArtist {
            place(spreadByAlbum(artist, items: items, using: &rng),
                  across: all.count, into: &placed, using: &rng)
        }
        return placed.sorted { $0.position < $1.position }.map(\.index)
    }

    private static func spreadByAlbum(_ group: [Int], items: [QueueItem], using rng: inout some RandomNumberGenerator) -> [Int] {
        let byAlbum = groups(of: group) { items[$0].track.albumId }
        guard byAlbum.count > 1 else { return group.shuffled(using: &rng) }

        var placed: [(position: Double, index: Int)] = []
        placed.reserveCapacity(group.count)
        for album in byAlbum {
            place(album.shuffled(using: &rng), across: group.count, into: &placed, using: &rng)
        }
        return placed.sorted { $0.position < $1.position }.map(\.index)
    }

    /// Jitter stays well under half the interval, so members keep their given order and
    /// can't land on top of each other — consecutive members stay ≥ 0.6 intervals apart.
    private static func place(_ ordered: [Int], across span: Int, into placed: inout [(position: Double, index: Int)], using rng: inout some RandomNumberGenerator) {
        let spacing = Double(span) / Double(ordered.count)
        let offset = Double.random(in: 0..<spacing, using: &rng)
        for (j, index) in ordered.enumerated() {
            let jitter = Double.random(in: -0.2...0.2, using: &rng) * spacing
            placed.append((offset + Double(j) * spacing + jitter, index))
        }
    }

    /// Grouped in a deterministic order so a seeded generator reproduces a shuffle.
    private static func groups(of indices: [Int], by key: (Int) -> UUID) -> [[Int]] {
        Dictionary(grouping: indices, by: key)
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map(\.value)
    }
}
