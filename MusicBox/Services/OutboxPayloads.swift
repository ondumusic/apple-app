import Foundation

nonisolated enum OutboxKind: String, Sendable {
    case createPlaylist = "create_playlist"
    case renamePlaylist = "rename_playlist"
    case movePlaylist   = "move_playlist"
    case deletePlaylist = "delete_playlist"
    case addItems       = "add_items"
    case moveItems      = "move_items"
    case removeItems    = "remove_items"
}

nonisolated struct CreatePlaylistPayload: Codable, Sendable {
    var tempPlaylistId: UUID
    var name: String
    var isFolder: Bool
    var parentId: UUID?

    init(tempPlaylistId: UUID, name: String, isFolder: Bool = false, parentId: UUID? = nil) {
        self.tempPlaylistId = tempPlaylistId
        self.name = name
        self.isFolder = isFolder
        self.parentId = parentId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tempPlaylistId = try c.decode(UUID.self, forKey: .tempPlaylistId)
        name = try c.decode(String.self, forKey: .name)
        isFolder = try c.decodeIfPresent(Bool.self, forKey: .isFolder) ?? false
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
    }
}

nonisolated struct RenamePlaylistPayload: Codable, Sendable {
    var playlistId: UUID
    var name: String
}

/// Reparents a playlist or folder. `parentId == nil` means root.
nonisolated struct MovePlaylistPayload: Codable, Sendable {
    var playlistId: UUID
    var parentId: UUID?
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

nonisolated struct MoveItemsPayload: Codable, Sendable {
    nonisolated struct Entry: Codable, Sendable {
        var itemId: UUID
        var position: String
    }
    var playlistId: UUID
    var items: [Entry]
}

nonisolated struct RemoveItemsPayload: Codable, Sendable {
    var playlistId: UUID
    var itemIds: [UUID]
}
