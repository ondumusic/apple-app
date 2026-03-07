import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case search = "Search"
    case downloads = "Downloads"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct macOSRootView: View {
    @Environment(NetworkMonitor.self) private var network
    @State private var selection: SidebarItem? = .artists
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
        if !network.isOnline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                Text("Offline — only downloaded music is available")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
        }

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
                case .search:
                    SearchView(query: searchText)
                        .searchable(text: $searchText, prompt: "Artists, albums, or songs")
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
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            navigationPath = NavigationPath()
            selection = .artists
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigationPath.append(artist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            navigationPath = NavigationPath()
            selection = .albums
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigationPath.append(album)
            }
        }
        } // VStack
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
