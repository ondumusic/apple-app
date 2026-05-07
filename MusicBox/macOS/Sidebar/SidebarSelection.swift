#if os(macOS)
import Foundation

nonisolated enum SidebarCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case artists
    case albums
    case songs
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .downloads: "Downloads"
        }
    }

    /// SF Symbol name shown in the sidebar row.
    var iconName: String {
        switch self {
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .downloads: "arrow.down.circle"
        }
    }
}

nonisolated enum SidebarSelection: Hashable, Sendable {
    case category(SidebarCategory)
    case playlist(UUID)
}
#endif
