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

    private func request(for endpoint: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch<T: Decodable & Sendable>(_ endpoint: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let req = try request(for: endpoint, queryItems: queryItems)
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
        decoder.dateDecodingStrategy = .iso8601
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

    func deleteSession() async throws {
        var req = try request(for: "/auth/session")
        req.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return // Best-effort — still clear local state even if server call fails
        }
    }

    // MARK: - Sync

    func fetchSync(cursor: String? = nil) async throws -> SyncResponse {
        var queryItems: [URLQueryItem] = []
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await fetch("/sync", queryItems: queryItems)
    }

    // MARK: - Playlists

    nonisolated struct PositionedTrackBody: Encodable, Sendable {
        let trackId: UUID
        let position: String
    }

    nonisolated struct PositionedItemBody: Encodable, Sendable {
        let itemId: UUID
        let position: String
    }

    nonisolated struct UpdatePlaylistItemsBody: Encodable, Sendable {
        let add: [PositionedTrackBody]
        let move: [PositionedItemBody]
        let remove: [UUID]
    }

    nonisolated struct UpdatePlaylistItemsResponse: Decodable, Sendable {
        var added: [PlaylistItem]
        var moved: [PlaylistItem]
        var removed: [UUID]

        nonisolated enum CodingKeys: String, CodingKey {
            case added, moved, removed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            added = try container.decodeIfPresent([PlaylistItem].self, forKey: .added) ?? []
            moved = try container.decodeIfPresent([PlaylistItem].self, forKey: .moved) ?? []
            removed = try container.decodeIfPresent([UUID].self, forKey: .removed) ?? []
        }
    }

    func createPlaylist(name: String) async throws -> Playlist {
        let body = try JSONEncoder.api.encode(["name": name])
        return try await perform("/playlists", method: "POST", body: body)
    }

    func renamePlaylist(_ id: UUID, name: String) async throws -> Playlist {
        let body = try JSONEncoder.api.encode(["name": name])
        return try await perform("/playlists/\(id.uuidString.lowercased())", method: "PATCH", body: body)
    }

    func deletePlaylist(_ id: UUID) async throws {
        let _: Playlist = try await perform("/playlists/\(id.uuidString.lowercased())", method: "DELETE", body: nil)
    }

    func updatePlaylistItems(_ id: UUID,
                             add: [PositionedTrackBody] = [],
                             move: [PositionedItemBody] = [],
                             remove: [UUID] = []) async throws -> UpdatePlaylistItemsResponse {
        let body = try JSONEncoder.api.encode(UpdatePlaylistItemsBody(add: add, move: move, remove: remove))
        return try await perform("/playlists/\(id.uuidString.lowercased())/items", method: "PATCH", body: body)
    }

    // MARK: - Mutation helper

    private func perform<T: Decodable & Sendable>(_ endpoint: String, method: String, body: Data?) async throws -> T {
        var req = try request(for: endpoint)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
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

extension JSONDecoder {
    nonisolated(unsafe) static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    nonisolated(unsafe) static let api: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
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
