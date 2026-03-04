import Foundation

nonisolated struct Artist: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var slug: String
    var albumCount: Int?
}
