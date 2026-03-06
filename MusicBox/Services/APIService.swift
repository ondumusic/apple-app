import Foundation

@Observable
final class APIService: Sendable {
    let baseURL: URL
    let sessionToken: String

    init(baseURL: URL, sessionToken: String) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
    }

    // MARK: - Generic Fetch

    private func request(for endpoint: String, queryItems: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch<T: Decodable & Sendable>(_ endpoint: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let req = request(for: endpoint, queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw APIError.decoding("Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(type, context) {
            throw APIError.decoding("Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.valueNotFound(type, context) {
            throw APIError.decoding("Null value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Auth

    func fetchCurrentUser() async throws -> User {
        try await fetch("/auth/me")
    }

    func fetchPlayToken() async throws -> String {
        nonisolated struct PlayTokenResponse: Decodable, Sendable {
            var ok: Bool
            var playToken: String
        }
        let response: PlayTokenResponse = try await fetch("/auth/playtoken")
        return response.playToken
    }

    // MARK: - Browsing

    func fetchArtists(page: Int = 1) async throws -> Page<Artist> {
        try await fetch("/artists", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func fetchArtist(_ artistId: UUID) async throws -> Artist {
        try await fetch("/artists/\(artistId.uuidString.lowercased())")
    }

    func fetchAlbums(for artistId: UUID, page: Int = 1) async throws -> Page<Album> {
        try await fetch("/artists/\(artistId.uuidString.lowercased())/albums", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func fetchAlbum(_ albumId: UUID) async throws -> Album {
        try await fetch("/albums/\(albumId.uuidString.lowercased())")
    }

    func fetchAllAlbums(page: Int = 1) async throws -> Page<Album> {
        try await fetch("/albums", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func fetchTracks(page: Int = 1) async throws -> Page<Track> {
        try await fetch("/tracks", queryItems: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func fetchTrack(_ trackId: UUID) async throws -> Track {
        try await fetch("/tracks/\(trackId.uuidString.lowercased())")
    }

    /// Fetch all tracks matching filters, paging through all results.
    func fetchAllTracks(artistId: UUID? = nil, albumId: UUID? = nil) async throws -> [Track] {
        var all: [Track] = []
        var page = 1
        while true {
            var queryItems = [URLQueryItem(name: "page", value: "\(page)")]
            if let artistId {
                queryItems.append(URLQueryItem(name: "artist_id", value: artistId.uuidString.lowercased()))
            }
            if let albumId {
                queryItems.append(URLQueryItem(name: "album_id", value: albumId.uuidString.lowercased()))
            }
            let result: Page<Track> = try await fetch("/tracks", queryItems: queryItems)
            all.append(contentsOf: result.entries)
            if page >= result.totalPages { break }
            page += 1
        }
        return all
    }

    /// Fetch all albums for an artist (with tracks loaded), paging through all results.
    func fetchArtistAlbumsWithTracks(artistId: UUID) async throws -> [Album] {
        let stubs = try await fetchAllAlbums(for: artistId)
        return try await withThrowingTaskGroup(of: Album.self) { group in
            for stub in stubs {
                group.addTask { try await self.fetchAlbum(stub.id) }
            }
            var albums: [Album] = []
            for try await album in group {
                albums.append(album)
            }
            return albums
        }
    }

    /// Fetch all albums for an artist, paging through all results.
    func fetchAllAlbums(for artistId: UUID) async throws -> [Album] {
        var all: [Album] = []
        var page = 1
        while true {
            let result = try await fetchAlbums(for: artistId, page: page)
            all.append(contentsOf: result.entries)
            if page >= result.totalPages { break }
            page += 1
        }
        return all
    }

    // MARK: - Static Auth (no token needed)

    nonisolated struct LoginResponse: Decodable, Sendable {
        var ok: Bool
        var sessionToken: String?
        var currentUser: User?
        var fields: LoginFields?

        nonisolated struct LoginFields: Decodable, Sendable {
            var password: FieldError?

            nonisolated struct FieldError: Decodable, Sendable {
                var message: String
            }
        }
    }

    static func login(baseURL: URL, username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = ["username": username, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...401).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LoginResponse.self, from: data)
    }
}

nonisolated enum APIError: LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case httpError(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .unauthorized: "Session expired. Please log in again."
        case .httpError(let code): "Server error (\(code))"
        case .decoding(let detail): "Decoding error: \(detail)"
        }
    }
}
