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
    var renamePlaylist: (Playlist) -> Void = { _ in }
    var deletePlaylist: (Playlist) -> Void = { _ in }
    /// Track IDs being dropped onto a (non-folder) playlist row. Caller adds them via
    /// the playlist controller / outbox.
    var addTracksToPlaylist: ([UUID], Playlist) -> Void = { _, _ in }
    /// Trigger naming flow for a new playlist; parentId nil = root.
    var createPlaylist: (UUID?) -> Void = { _ in }
    /// Trigger naming flow for a new folder; parentId nil = root.
    var createFolder: (UUID?) -> Void = { _ in }
}

extension NSPasteboard.PasteboardType {
    /// Pasteboard type used by track drag operations. Carries one UUID string per
    /// dragged track in NSPasteboardItem(s).
    static let musicBoxTracks = NSPasteboard.PasteboardType("com.musicbox.tracks")
}
#endif
