#if os(macOS)
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"
    case search = "Search"
    case playlists = "Playlists"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .search: "magnifyingglass"
        case .playlists: "music.note.list"
        }
    }
}

struct macOSRootView: View {
    @Environment(AuthService.self) private var authService
    @AppStorage("selectedSidebarItem") private var selectionRaw: String = SidebarItem.artists.rawValue

    /// Migrates the retired `downloads` sidebar value to `artists`.
    private var selection: SidebarItem? {
        SidebarItem(rawValue: selectionRaw) ?? .artists
    }
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var showReAuth = false
    @State private var showDownloads = false

    var body: some View {
        VStack(spacing: 0) {
        if authService.isSessionExpired {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("Session expired")
                    .font(.caption)
                Spacer()
                Button("Re-authenticate") {
                    showReAuth = true
                }
                .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(.orange)
        }

        HStack(spacing: 0) {
            MacOSPlayerToolbar()
                .frame(maxWidth: .infinity)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            UserMenuButton(onDownloads: { showDownloads = true })
                .padding(.trailing, 12)
        }
        .background(.bar)

        NavigationSplitView {
            List(SidebarItem.allCases, selection: sidebarSelection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
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
                    SearchView(query: searchText, path: $navigationPath)
                        .searchable(text: $searchText, prompt: "Artists, albums, or songs")
                case .playlists:
                    PlaylistListView()
                case nil:
                    Text("Select a category")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .queueConfirmationOverlay()
        .replaceQueueConfirmation()
        .sheet(isPresented: $showReAuth) {
            ReAuthView()
        }
        .sheet(isPresented: $showDownloads) {
            NavigationStack {
                DownloadsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDownloads = false }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 480)
        }
        .onChange(of: authService.isSessionExpired) { _, expired in
            if expired { showReAuth = true }
            if !expired { showReAuth = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
            showReAuth = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            showDownloads = false
            navigationPath = NavigationPath()
            selectionRaw = SidebarItem.artists.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigationPath.append(artist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            showDownloads = false
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
#endif
