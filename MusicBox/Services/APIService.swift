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

    func fetchPlayToken() async throws -> String {
        nonisolated struct PlayTokenResponse: Decodable, Sendable {
            var ok: Bool
            var playToken: String
        }
        let response: PlayTokenResponse = try await fetch("/auth/playtoken")
        return response.playToken
    }

    // MARK: - Sync

    func fetchSync(cursor: String? = nil) async throws -> SyncResponse {
        var queryItems: [URLQueryItem] = []
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await fetch("/sync", queryItems: queryItems)
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
