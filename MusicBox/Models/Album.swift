import Foundation

nonisolated struct Album: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var artistId: UUID
    var name: String
    var slug: String
    var releaseYear: Int?
    var tracks: [Track]?
    var isUnknown: Bool
    var artworkUrl: URL?

    mutating func resolveURLs(against baseURL: URL) {
        if let artworkUrl, artworkUrl.host == nil {
            var components = URLComponents()
            components.scheme = baseURL.scheme
            components.host = baseURL.host
            components.port = baseURL.port
            components.path = artworkUrl.path
            self.artworkUrl = components.url
        }
    }
}
