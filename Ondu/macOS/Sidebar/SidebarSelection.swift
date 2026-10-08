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

    /// Round-trips through UserDefaults so a relaunch reopens where you left off.
    var storageValue: String {
        switch self {
        case .category(let category): "category:\(category.rawValue)"
        case .playlist(let id): "playlist:\(id.uuidString)"
        }
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "category":
            guard let category = SidebarCategory(rawValue: parts[1]) else { return nil }
            self = .category(category)
        case "playlist":
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .playlist(id)
        default:
            return nil
        }
    }
}
#endif
