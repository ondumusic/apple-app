import Foundation

nonisolated actor PlayTokenManager {
    private var cachedToken: String?
    private var fetchedAt: Date?

    func validToken(using api: APIService) async throws -> String {
        if let cachedToken, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 55 * 60 {
            return cachedToken
        }
        let token = try await api.fetchPlayToken()
        cachedToken = token
        fetchedAt = Date()
        return token
    }

    func resolvedStreamURL(for track: Track, using api: APIService) async throws -> URL {
        let token = try await validToken(using: api)
        guard let streamURL = URL(string: track.streamUrl) else {
            throw PlayTokenError.invalidStreamURL
        }
        // Resolve relative URL against baseURL scheme+host+port
        let resolved: URL
        if streamURL.host == nil {
            var components = URLComponents()
            components.scheme = api.baseURL.scheme
            components.host = api.baseURL.host
            components.port = api.baseURL.port
            components.path = streamURL.path
            guard let built = components.url else {
                throw PlayTokenError.invalidStreamURL
            }
            resolved = built
        } else {
            resolved = streamURL
        }
        guard var finalComponents = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            throw PlayTokenError.invalidStreamURL
        }
        var queryItems = finalComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        finalComponents.queryItems = queryItems
        guard let finalURL = finalComponents.url else {
            throw PlayTokenError.invalidStreamURL
        }
        return finalURL
    }
}

nonisolated enum PlayTokenError: LocalizedError, Sendable {
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .invalidStreamURL: "Invalid stream URL"
        }
    }
}
