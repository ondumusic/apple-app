import Foundation

nonisolated struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    var pageNumber: Int
    var pageSize: Int
    var totalPages: Int
    var totalEntries: Int
    var entries: [T]
}