import Foundation

nonisolated enum OutboxKind: String, Sendable {
    case createPlaylist = "create_playlist"
    case renamePlaylist = "rename_playlist"
    case deletePlaylist = "delete_playlist"
    case addItems       = "add_items"
    case removeItems    = "remove_items"
}

nonisolated struct CreatePlaylistPayload: Codable, Sendable {
    var tempPlaylistId: UUID
    var name: String
}

nonisolated struct RenamePlaylistPayload: Codable, Sendable {
    var playlistId: UUID
    var name: String
}

nonisolated struct DeletePlaylistPayload: Codable, Sendable {
    var playlistId: UUID
}

nonisolated struct AddItemsPayload: Codable, Sendable {
    nonisolated struct Entry: Codable, Sendable {
        var tempItemId: UUID
        var trackId: UUID
        var position: String
    }
    var playlistId: UUID
    var items: [Entry]
}

nonisolated struct RemoveItemsPayload: Codable, Sendable {
    var playlistId: UUID
    var itemIds: [UUID]
}
