import Foundation

nonisolated struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    var pageNumber: Int
    var pageSize: Int
    var totalPages: Int
    var totalEntries: Int
    var entries: [T]
}

extension Page where T == Album {
    mutating func resolveAlbumURLs(against baseURL: URL) {
        entries = entries.map { var a = $0; a.resolveURLs(against: baseURL); return a }
    }
}
