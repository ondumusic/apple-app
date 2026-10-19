import Foundation

@Observable
final class APIService: Sendable {
    let baseURL: URL
    let sessionToken: String

    init(baseURL: URL, sessionToken: String) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
    }

    /// Whether `url` may carry the session token. Stream and download URLs arrive in the
    /// server's own data; one pointing at another host is requested without the token
    /// rather than handing it to that host.
    func mayReceiveToken(_ url: URL) -> Bool {
        Self.isSameOrigin(url, as: baseURL)
    }

    /// Same scheme, host and port — a default port counting the same as one spelled out.
    nonisolated static func isSameOrigin(_ url: URL, as base: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == base.scheme?.lowercased(),
            let host = url.host()?.lowercased(), host == base.host()?.lowercased()
        else { return false }
        let defaultPort = ["https": 443, "http": 80][scheme]
        return (url.port ?? defaultPort) == (base.port ?? defaultPort)
    }

    // MARK: - Generic Fetch

    private func request(for endpoint: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard
            var components = URLComponents(
                url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        else {
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
            throw APIError.decoding(
                "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(type, context) {
            throw APIError.decoding(
                "Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.valueNotFound(type, context) {
            throw APIError.decoding(
                "Null value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
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
            return  // Best-effort — still clear local state even if server call fails
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

    // MARK: - Artist Artwork

    /// Why the server rejected an image, when it says.
    nonisolated enum ArtworkError: Error, Sendable {
        case notAnImage
        case tooLarge

        nonisolated struct DecodedBody: Decodable {
            let error: String
        }

        static func decode(_ data: Data) -> ArtworkError? {
            guard let body = try? JSONDecoder.api.decode(DecodedBody.self, from: data) else { return nil }
            switch body.error {
            case "invalid_image": return .notAnImage
            case "too_large": return .tooLarge
            default: return nil
            }
        }
    }

    /// Replaces the artist's artwork, returning the artist as the server now has it.
    ///
    /// Not through the outbox: that queue exists to replay small ordered mutations after
    /// being offline, and neither half fits an upload of several megabytes.
    func uploadArtistArtwork(
        artistId: UUID, imageData: Data, filename: String,
        mimeType: String
    ) async throws -> Artist {
        let boundary = "ondu.\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")

        var req = try request(for: "/artists/\(artistId.uuidString.lowercased())/artwork")
        req.httpMethod = "PUT"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.upload(for: req, from: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 422, let error = ArtworkError.decode(data) { throw error }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        do {
            return try JSONDecoder.api.decode(Artist.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func deleteArtistArtwork(artistId: UUID) async throws -> Artist {
        try await perform(
            "/artists/\(artistId.uuidString.lowercased())/artwork",
            method: "DELETE", body: nil)
    }

    // MARK: - Notices

    nonisolated struct NoticesResponse: Decodable, Sendable {
        let notices: [ServerNotice]
    }

    /// Dismisses for everyone, not just this device — the server clears it outright and
    /// hands back what's left.
    func dismissNotice(id: UUID) async throws -> [ServerNotice] {
        let response: NoticesResponse = try await perform(
            "/notices/\(id.uuidString.lowercased())/dismiss", method: "POST", body: nil)
        return response.notices
    }

    // MARK: - Server Info

    /// The API generation this build is written against. The server bumps its own only
    /// when it changes the API in a way that breaks existing clients, so any difference
    /// means one side can't talk to the other.
    nonisolated static let supportedAPIVersion = 1

    nonisolated struct ServerInfo: Decodable, Sendable {
        let version: String
        let apiVersion: Int
    }

    func fetchServerInfo() async throws -> ServerInfo {
        try await fetch("/info")
    }

    // MARK: - Plays

    nonisolated struct PlayBody: Encodable, Sendable {
        let id: String
        let trackId: String
        let playedAt: Date

        init(id: UUID, trackId: UUID, playedAt: Date) {
            self.id = id.uuidString.lowercased()
            self.trackId = trackId.uuidString.lowercased()
            self.playedAt = playedAt
        }
    }

    nonisolated struct RecordPlaysBody: Encodable, Sendable {
        let plays: [PlayBody]
    }

    func recordPlays(_ plays: [PlayBody]) async throws {
        let body = try JSONEncoder.api.encode(RecordPlaysBody(plays: plays))
        let _: RecordPlaysResponse = try await perform("/plays", method: "POST", body: body)
    }

    nonisolated struct RecordPlaysResponse: Decodable, Sendable {
        let ok: Bool
    }

    // MARK: - Playlists

    /// Server stores UUIDs lowercase; Swift's default `UUID` encoding emits uppercase. These body
    /// structs take UUIDs at construction time and lowercase them for the wire.
    nonisolated struct PositionedTrackBody: Encodable, Sendable {
        let trackId: String
        let position: String

        init(trackId: UUID, position: String) {
            self.trackId = trackId.uuidString.lowercased()
            self.position = position
        }
    }

    nonisolated struct PositionedItemBody: Encodable, Sendable {
        let itemId: String
        let position: String

        init(itemId: UUID, position: String) {
            self.itemId = itemId.uuidString.lowercased()
            self.position = position
        }
    }

    nonisolated struct UpdatePlaylistItemsBody: Encodable, Sendable {
        let add: [PositionedTrackBody]
        let move: [PositionedItemBody]
        let remove: [String]

        init(add: [PositionedTrackBody], move: [PositionedItemBody], remove: [UUID]) {
            self.add = add
            self.move = move
            self.remove = remove.map { $0.uuidString.lowercased() }
        }
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

    /// Discriminated error returned as HTTP 422 by PATCH /playlists/{id}/items. The caller
    /// can recover from `unknownTracks` / `unknownItems` by filtering and retrying; the
    /// conflict cases, `tooManyOperations`, and `playlistIsFolder` are surfaced as errors.
    nonisolated enum PlaylistItemsError: Error, Sendable {
        case tooManyOperations
        case duplicateItems(itemIds: [UUID])
        case moveRemoveConflict(itemIds: [UUID])
        case unknownItems(itemIds: [UUID])
        case unknownTracks(trackIds: [UUID])
        case invalidPositions(positions: [String])
        case playlistIsFolder

        nonisolated struct DecodedBody: Decodable {
            let error: String
            let itemIds: [UUID]?
            let trackIds: [UUID]?
            let positions: [String]?
        }

        static func decode(_ data: Data) -> PlaylistItemsError? {
            guard let body = try? JSONDecoder.api.decode(DecodedBody.self, from: data) else { return nil }
            switch body.error {
            case "too_many_operations": return .tooManyOperations
            case "duplicate_items": return .duplicateItems(itemIds: body.itemIds ?? [])
            case "move_remove_conflict": return .moveRemoveConflict(itemIds: body.itemIds ?? [])
            case "unknown_items": return .unknownItems(itemIds: body.itemIds ?? [])
            case "unknown_tracks": return .unknownTracks(trackIds: body.trackIds ?? [])
            case "invalid_positions": return .invalidPositions(positions: body.positions ?? [])
            case "playlist_is_folder": return .playlistIsFolder
            default: return nil
            }
        }
    }

    nonisolated struct CreatePlaylistBody: Encodable, Sendable {
        let name: String
        let isFolder: Bool
        let parentId: String?

        init(name: String, isFolder: Bool, parentId: UUID?) {
            self.name = name
            self.isFolder = isFolder
            self.parentId = parentId?.uuidString.lowercased()
        }
    }

    nonisolated struct UpdatePlaylistBody: Encodable, Sendable {
        let name: String?
        let parentId: String?
        let parentIdIsExplicit: Bool

        nonisolated enum CodingKeys: String, CodingKey {
            case name, parentId
        }

        init(name: String?, parentId: UUID??) {
            self.name = name
            // `parentId: UUID??` lets us distinguish "don't touch" (nil outer) from
            // "set to root" (.some(nil)). The server treats parentId=null as root.
            switch parentId {
            case .none:
                self.parentId = nil
                self.parentIdIsExplicit = false
            case .some(let inner):
                self.parentId = inner?.uuidString.lowercased()
                self.parentIdIsExplicit = true
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let name { try c.encode(name, forKey: .name) }
            if parentIdIsExplicit { try c.encode(parentId, forKey: .parentId) }
        }
    }

    func createPlaylist(name: String, isFolder: Bool = false, parentId: UUID? = nil) async throws -> Playlist {
        let body = try JSONEncoder.api.encode(CreatePlaylistBody(name: name, isFolder: isFolder, parentId: parentId))
        return try await perform("/playlists", method: "POST", body: body)
    }

    func renamePlaylist(_ id: UUID, name: String) async throws -> Playlist {
        let body = try JSONEncoder.api.encode(UpdatePlaylistBody(name: name, parentId: nil))
        return try await perform("/playlists/\(id.uuidString.lowercased())", method: "PATCH", body: body)
    }

    func movePlaylist(_ id: UUID, to parentId: UUID?) async throws -> Playlist {
        let body = try JSONEncoder.api.encode(UpdatePlaylistBody(name: nil, parentId: .some(parentId)))
        return try await perform("/playlists/\(id.uuidString.lowercased())", method: "PATCH", body: body)
    }

    func deletePlaylist(_ id: UUID) async throws {
        let _: Playlist = try await perform("/playlists/\(id.uuidString.lowercased())", method: "DELETE", body: nil)
    }

    func updatePlaylistItems(
        _ id: UUID,
        add: [PositionedTrackBody] = [],
        move: [PositionedItemBody] = [],
        remove: [UUID] = []
    ) async throws -> UpdatePlaylistItemsResponse {
        var req = try request(for: "/playlists/\(id.uuidString.lowercased())/items")
        req.httpMethod = "PATCH"
        req.httpBody = try JSONEncoder.api.encode(UpdatePlaylistItemsBody(add: add, move: move, remove: remove))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }

        // Typed recovery for the discriminated error union — callers can inspect which items
        // or tracks the server rejected and retry with them filtered out.
        if http.statusCode == 422, let typed = PlaylistItemsError.decode(data) {
            #if DEBUG
            print("APIService: PATCH /playlists/\(id.uuidString.lowercased())/items 422 — \(typed)")
            #endif
            throw typed
        }

        guard (200...299).contains(http.statusCode) else {
            #if DEBUG
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
            print(
                "APIService: PATCH /playlists/\(id.uuidString.lowercased())/items failed — HTTP \(http.statusCode), body: \(bodyString)"
            )
            #endif
            throw APIError.httpError(http.statusCode)
        }
        do {
            return try JSONDecoder.api.decode(UpdatePlaylistItemsResponse.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
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
            #if DEBUG
            let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
            print("APIService: \(method) \(endpoint) failed — HTTP \(http.statusCode), body: \(bodyString)")
            #endif
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

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 422:
            throw LoginRejection.invalidCredentials
        case 429:
            throw LoginRejection.tooManyAttempts
        default:
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

/// The server's own field messages aren't used: which field it blames would tell someone
/// guessing at accounts whether the username exists.
nonisolated enum LoginRejection: LocalizedError, Sendable {
    case invalidCredentials
    case tooManyAttempts

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: String(localized: "Wrong username or password.")
        case .tooManyAttempts: String(localized: "Too many failed attempts. Wait a few minutes and try again.")
        }
    }
}

extension Data {
    fileprivate mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
