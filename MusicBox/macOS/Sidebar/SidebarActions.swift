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
}

extension NSPasteboard.PasteboardType {
    /// Pasteboard type used by track drag operations. Carries one UUID string per
    /// dragged track in NSPasteboardItem(s).
    static let musicBoxTracks = NSPasteboard.PasteboardType("com.musicbox.tracks")
    /// Pasteboard type used by sidebar playlist drag operations. Distinct from
    /// musicBoxTracks so a track drag can't accidentally land as a playlist move.
    static let musicBoxSidebarPlaylist = NSPasteboard.PasteboardType("com.musicbox.sidebar.playlist")
}
#endif
