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
    @Environment(AuthService.self) private var authService
    @Environment(NetworkMonitor.self) private var network
    @AppStorage("selectedSidebarItem") private var selectionRaw: String = SidebarItem.artists.rawValue

    private var selection: SidebarItem? { SidebarItem(rawValue: selectionRaw) }
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
        if authService.isSessionExpired {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("Session expired — please log in again")
                    .font(.caption)
                Spacer()
                Button("Log In") {
                    authService.logout()
                }
                .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(.red)
        } else if !network.isOnline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                Text("Offline — only downloaded music is available")
                    .font(.caption)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.yellow)
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
        .queueConfirmationOverlay()
        .replaceQueueConfirmation()
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            navigationPath = NavigationPath()
            selectionRaw = SidebarItem.artists.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigationPath.append(artist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            navigationPath = NavigationPath()
            selectionRaw = SidebarItem.albums.rawValue
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
            selectionRaw = newValue?.rawValue ?? SidebarItem.artists.rawValue
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
