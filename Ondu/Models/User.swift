import Foundation

nonisolated struct User: Codable, Identifiable, Sendable {
    var id: UUID
    var username: String
}
