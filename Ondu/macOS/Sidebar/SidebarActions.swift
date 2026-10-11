#if os(macOS)
import AppKit
import Foundation

/// Actions the sidebar can invoke. Populated by MacOSContentView from its
/// SwiftUI @Environment values, so the AppKit outline view can fire work without
/// reaching back into the SwiftUI environment from inside an NSMenu action.
@MainActor
struct SidebarActions {
    var playPlaylist: (Playlist) -> Void = { _ in }
    var shufflePlaylist: (Playlist) -> Void = { _ in }
    /// Commit a rename. Inline edit fires this when the user presses Enter / blurs the
    /// inline text field with a non-empty value different from the current name.
    var renamePlaylist: (Playlist, String) -> Void = { _, _ in }
    var deletePlaylist: (Playlist) -> Void = { _ in }
    /// Track IDs being dropped onto a (non-folder) playlist row. Caller adds them via
    /// the playlist controller / outbox.
    var addTracksToPlaylist: ([UUID], Playlist) -> Void = { _, _ in }
    /// Albums are resolved to their tracks by the caller, which is the side that has
    /// the library.
    var addAlbumsToPlaylist: ([UUID], Playlist) -> Void = { _, _ in }
    /// Trigger naming flow for a new playlist; parentId nil = root.
    var createPlaylist: (UUID?) -> Void = { _ in }
    /// Trigger naming flow for a new folder; parentId nil = root.
    var createFolder: (UUID?) -> Void = { _ in }
    /// Download every track in the playlist, or remove those downloads. The sidebar
    /// asks whether it's fully downloaded to decide which of the two to offer.
    var downloadPlaylist: (Playlist) -> Void = { _ in }
    var removePlaylistDownload: (Playlist) -> Void = { _ in }
    var isPlaylistDownloaded: (Playlist) -> Bool = { _ in false }
    /// Move playlist (or folder) into the given parent. Nil parent = root.
    var movePlaylist: (UUID, UUID?) -> Void = { _, _ in }
    var addArtistsToPlaylist: ([UUID], Playlist) -> Void = { _, _ in }
}

extension NSPasteboard.PasteboardType {
    /// Pasteboard type used by track drag operations. Carries one UUID string per
    /// dragged track in NSPasteboardItem(s).
    static let onduTracks = NSPasteboard.PasteboardType("com.ondumusic.tracks")
    /// Pasteboard type used by album drag operations. One album UUID per item — the
    /// drop side expands it to tracks, since a single NSPasteboardItem can only carry
    /// one string per type and an album is many tracks.
    static let onduAlbums = NSPasteboard.PasteboardType("com.ondumusic.albums")
    /// Pasteboard type used by artist drag operations. One artist UUID per item, expanded
    /// to that artist's albums on drop, for the same reason albums are.
    static let onduArtists = NSPasteboard.PasteboardType("com.ondumusic.artists")
    /// Pasteboard type used by sidebar playlist drag operations. Distinct from
    /// onduTracks so a track drag can't accidentally land as a playlist move.
    static let onduSidebarPlaylist = NSPasteboard.PasteboardType("com.ondumusic.sidebar.playlist")
}

extension NSDraggingInfo {
    /// The UUIDs a drag carries for one pasteboard type.
    ///
    /// Two kinds of writer feed these. AppKit tables and collection views write a string
    /// per `NSPasteboardItem`; SwiftUI's `.onDrag` hands over an `NSItemProvider`, which
    /// materialises the same bytes as raw data under a custom type identifier, and
    /// `string(forType:)` returns nil for that. Reading both is what lets a search
    /// result drop where a library row does.
    func onduIds(forType type: NSPasteboard.PasteboardType) -> [UUID] {
        let ids = (draggingPasteboard.pasteboardItems ?? []).compactMap { item -> UUID? in
            if let string = item.string(forType: type) { return UUID(uuidString: string) }
            guard let data = item.data(forType: type) else { return nil }
            return String(data: data, encoding: .utf8).flatMap(UUID.init(uuidString:))
        }
        if !ids.isEmpty { return ids }
        // A promised item can leave the pasteboard with the type declared but no item
        // carrying it until the data is pulled from the pasteboard itself.
        guard let data = draggingPasteboard.data(forType: type),
            let string = String(data: data, encoding: .utf8),
            let id = UUID(uuidString: string)
        else { return [] }
        return [id]
    }

    func carriesOnduType(_ types: NSPasteboard.PasteboardType...) -> Bool {
        let available = draggingPasteboard.types ?? []
        return types.contains { available.contains($0) }
    }
}
#endif
