import Foundation

enum SmartShuffle {
    static func shuffledIndices(for items: [QueueItem], spread: Bool) -> [Int] {
        var indices = Array(items.indices)
        indices.shuffle()
        guard spread, indices.count > 2 else { return indices }
        applySpread(&indices, items: items)
        return indices
    }

    private static func applySpread(_ indices: inout [Int], items: [QueueItem]) {
        let n = indices.count
        let albumIds = items.map { $0.track.albumId }
        let artistIds = items.map { $0.track.albumArtistId }

        let distinctAlbums = max(Set(albumIds).count, 1)
        let distinctArtists = max(Set(artistIds).count, 1)
        let albumGap = max(1, min(4, n / distinctAlbums - 1))
        let artistGap = max(1, min(2, n / distinctArtists - 1))

        let maxSwaps = n * 2
        var swaps = 0

        for i in 1..<n where swaps < maxSwaps {
            guard conflicts(at: i, in: indices, albumIds: albumIds, artistIds: artistIds, albumGap: albumGap, artistGap: artistGap) else { continue }
            guard let j = swapTarget(from: i, in: indices, albumIds: albumIds, artistIds: artistIds, albumGap: albumGap, artistGap: artistGap) else { continue }
            indices.swapAt(i, j)
            swaps += 1
        }
    }

    private static func conflicts(at i: Int, in indices: [Int], albumIds: [UUID], artistIds: [UUID], albumGap: Int, artistGap: Int) -> Bool {
        let cur = indices[i]
        let curAlbum = albumIds[cur]
        let curArtist = artistIds[cur]
        let aStart = max(0, i - albumGap)
        for k in aStart..<i where albumIds[indices[k]] == curAlbum { return true }
        let arStart = max(0, i - artistGap)
        for k in arStart..<i where artistIds[indices[k]] == curArtist { return true }
        return false
    }

    private static func swapTarget(from i: Int, in indices: [Int], albumIds: [UUID], artistIds: [UUID], albumGap: Int, artistGap: Int) -> Int? {
        let n = indices.count
        let aStart = max(0, i - albumGap)
        let arStart = max(0, i - artistGap)
        for j in (i + 1)..<n {
            let cand = indices[j]
            let candAlbum = albumIds[cand]
            let candArtist = artistIds[cand]
            var clash = false
            for k in aStart..<i where albumIds[indices[k]] == candAlbum { clash = true; break }
            if clash { continue }
            for k in arStart..<i where artistIds[indices[k]] == candArtist { clash = true; break }
            if !clash { return j }
        }
        return nil
    }
}
