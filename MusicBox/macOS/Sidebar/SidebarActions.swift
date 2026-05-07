#if os(macOS)
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
}
#endif
