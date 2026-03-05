import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case downloads = "Downloads"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct macOSRootView: View {
    @State private var selection: SidebarItem? = .artists
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: sidebarSelection) { item in
                if item == .downloads {
                    DownloadSidebarRow()
                        .tag(item)
                } else {
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            NavigationStack(path: $navigationPath) {
                switch selection {
                case .artists:
                    ArtistListView()
                case .albums:
                    AlbumListView()
                case .songs:
                    SongListView()
                case .downloads:
                    DownloadsView()
                case nil:
                    Text("Select a category")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                MacOSPlayerToolbar()
            }
        }
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding {
            selection
        } set: { newValue in
            if newValue == selection {
                navigationPath = NavigationPath()
            }
            selection = newValue
        }
    }
}

private struct DownloadSidebarRow: View {
    @Environment(DownloadService.self) private var downloadService

    private var count: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
    }

    var body: some View {
        Label("Downloads", systemImage: "arrow.down.circle")
            .badge(count)
    }
}
