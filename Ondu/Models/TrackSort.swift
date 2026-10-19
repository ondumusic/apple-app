import Foundation

/// A sort chosen by clicking a column header.
///
/// `nil` is not "unsorted" — it's the library's own order: album artist, album, disc,
/// track number. That order is why an album's tracks sit together instead of scattering,
/// and no single column expresses it, so it stays the default and the header menu offers
/// a way back to it.
nonisolated enum TrackSortColumn: String, CaseIterable, Sendable {
    case number
    case disc
    case title
    case artist
    case album
    case year
    case duration
    case plays
    case lastPlayed

    /// What this column sorts by, in order. Only the first is reversed when the sort is
    /// descending — the rest are the grouping beneath it, and reversing those would put
    /// an artist's albums in backwards order for no reason anyone asked for.
    var keys: [TrackSortKey] {
        switch self {
        case .number: return [.number, .albumArtist, .album, .disc]
        case .disc: return [.disc, .albumArtist, .album, .number]
        case .title: return [.title, .albumArtist, .album, .disc, .number]
        case .artist: return [.albumArtist, .album, .disc, .number]
        case .album: return [.album, .disc, .number]
        case .year: return [.year, .albumArtist, .album, .disc, .number]
        case .duration: return [.duration, .albumArtist, .album, .disc, .number]
        // Most libraries have a lot of tracks played exactly once, and "which of these
        // did I hear recently" is a better answer there than alphabetical.
        case .plays: return [.plays, .recentlyPlayed, .albumArtist, .album, .disc, .number]
        case .lastPlayed: return [.lastPlayed, .albumArtist, .album, .disc, .number]
        }
    }

    /// Which way the first click sorts. Alphabetical and numeric columns read forwards;
    /// play counts and dates are asked about from the top, so the first click puts the
    /// most played, and the most recently played, first rather than the pile of
    /// never-played ones.
    var defaultAscending: Bool {
        switch self {
        case .plays, .lastPlayed: return false
        default: return true
        }
    }
}

nonisolated enum TrackSortKey: Sendable {
    case number
    case disc
    case title
    case albumArtist
    case album
    case year
    case duration
    case plays
    case lastPlayed
    /// Last played, newest first, for use as a tiebreak. Keys after the first always sort
    /// ascending — that's what keeps an artist's albums in order under a reversed primary
    /// — so a newest-first tiebreak has to be its own key rather than a direction.
    case recentlyPlayed

    func compare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        switch self {
        case .number: return Self.compare(lhs.number ?? 0, rhs.number ?? 0)
        case .disc: return Self.compare(lhs.disc, rhs.disc)
        case .title: return lhs.name.localizedStandardCompare(rhs.name)
        // The album artist by its sort name: it's the value the Artist column shows, and
        // the one the library's default order uses, so "The Beatles" files under B in
        // both.
        case .albumArtist: return lhs.albumArtistSortName.localizedStandardCompare(rhs.albumArtistSortName)
        case .album: return (lhs.album?.name ?? "").localizedStandardCompare(rhs.album?.name ?? "")
        case .year: return Self.compare(lhs.album?.releaseYear ?? 0, rhs.album?.releaseYear ?? 0)
        case .duration: return Self.compare(lhs.duration, rhs.duration)
        case .plays: return Self.compare(lhs.playCount, rhs.playCount)
        // Never played sorts as longest ago, so descending puts it last where it belongs
        // rather than above everything that has been played.
        case .lastPlayed:
            return Self.compare(lhs.lastPlayedAt ?? .distantPast, rhs.lastPlayedAt ?? .distantPast)
        case .recentlyPlayed:
            return Self.compare(rhs.lastPlayedAt ?? .distantPast, lhs.lastPlayedAt ?? .distantPast)
        }
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }
}

nonisolated struct TrackSort: Equatable, Sendable, RawRepresentable {
    /// Where the Songs view keeps its sort, read too by the sidebar's Play on that row.
    static let songsKey = "songsSort"

    var column: TrackSortColumn
    var ascending: Bool

    init(column: TrackSortColumn, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }

    /// Stored in `@AppStorage`, which wants a plain value.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let column = TrackSortColumn(rawValue: String(parts[0])) else { return nil }
        self.column = column
        self.ascending = parts[1] == "asc"
    }

    var rawValue: String { "\(column.rawValue):\(ascending ? "asc" : "desc")" }

    func sorted(_ tracks: [Track]) -> [Track] {
        let keys = column.keys
        return tracks.sorted { lhs, rhs in
            for (index, key) in keys.enumerated() {
                let order = key.compare(lhs, rhs)
                guard order != .orderedSame else { continue }
                let wantAscending = index == 0 ? ascending : true
                return wantAscending ? order == .orderedAscending : order == .orderedDescending
            }
            // Everything the column groups by is equal; keep it stable by title.
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
