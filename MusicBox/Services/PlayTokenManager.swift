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

    func invalidate() {
        cachedToken = nil
        fetchedAt = nil
    }

    func resolvedStreamURL(for track: Track, using api: APIService) async throws -> URL {
        let token = try await validToken(using: api)
        guard let streamURL = URL(string: track.streamUrl) else {
            throw PlayTokenError.invalidStreamURL
        }
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else {
            throw PlayTokenError.invalidStreamURL
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token))
        components.queryItems = queryItems
        guard let finalURL = components.url else {
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
