#if os(iOS)
import SwiftUI

nonisolated enum iOSTab: String, Hashable, Sendable {
    case artists, albums, songs, search, playlists
}


struct iOSRootView: View {
    @Environment(AuthService.self) private var authService
    @Environment(DownloadService.self) private var downloadService
    @State private var showSettings = false
    @State private var showDownloads = false
    @State private var showReAuth = false
    @State private var addToPlaylistTrackIds: [UUID] = []
    @AppStorage("selectedTab") private var selectedTabRaw: String = iOSTab.artists.rawValue
    @State private var artistsPath = NavigationPath()
    @State private var albumsPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var playlistsPath = NavigationPath()
    @State private var searchText = ""

    private var selectedTab: iOSTab {
        // Migrate the retired `.downloads` value to `.artists`.
        iOSTab(rawValue: selectedTabRaw) ?? .artists
    }

    private func postScrollToTop() {
        NotificationCenter.default.post(name: .scrollToTop, object: nil)
    }

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
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.orange)
        }

        TabView(selection: tabSelection) {
            Tab("Artists", systemImage: "music.mic", value: .artists) {
                NavigationStack(path: $artistsPath) {
                    ArtistListView()
                        .toolbar { userMenu }
                }
                .nowPlayingBar()
            }

            Tab("Albums", systemImage: "square.stack", value: .albums) {
                NavigationStack(path: $albumsPath) {
                    AlbumListView()
                        .toolbar { userMenu }
                }
                .nowPlayingBar()
            }

            Tab("Songs", systemImage: "music.note", value: .songs) {
                NavigationStack {
                    SongListView()
                        .toolbar { userMenu }
                }
                .nowPlayingBar()
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(query: searchText, path: $searchPath)
                        .navigationTitle("Search")
                        // .always, not the default: the automatic placement tucks the
                        // field under the navigation bar whenever the content scrolls, so
                        // arriving at the Search tab with a long history meant scrolling
                        // up to find the one control the tab exists for.
                        .searchable(text: $searchText,
                                    placement: .navigationBarDrawer(displayMode: .always),
                                    prompt: "Artists, albums, or songs")
                        .toolbar { userMenu }
                }
                .nowPlayingBar()
            }

            Tab("Playlists", systemImage: "music.note.list", value: .playlists) {
                NavigationStack(path: $playlistsPath) {
                    PlaylistListView()
                        .toolbar { userMenu }
                }
                .nowPlayingBar()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            showDownloads = false
            artistsPath = NavigationPath()
            selectedTabRaw = iOSTab.artists.rawValue
            // Delay slightly so tab switch completes before push
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                artistsPath.append(artist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            showDownloads = false
            albumsPath = NavigationPath()
            selectedTabRaw = iOSTab.albums.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                albumsPath.append(album)
            }
        }
        .queueConfirmationOverlay()
        .replaceQueueConfirmation()
        .sheet(isPresented: $showReAuth) {
            ReAuthView()
        }
        .onChange(of: authService.isSessionExpired) { _, expired in
            if expired { showReAuth = true }
            if !expired { showReAuth = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
            showReAuth = true
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
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
            .nowPlayingBar()
        }
        .sheet(
            isPresented: Binding(
                get: { !addToPlaylistTrackIds.isEmpty },
                set: { if !$0 { addToPlaylistTrackIds = [] } }
            )
        ) {
            AddToPlaylistSheet(trackIds: addToPlaylistTrackIds)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestAddToPlaylist)) { notification in
            guard let ids = notification.object as? [UUID], !ids.isEmpty else { return }
            addToPlaylistTrackIds = ids
        }
        } // VStack
    }

    private var tabSelection: Binding<iOSTab> {
        Binding {
            selectedTab
        } set: { newTab in
            if newTab == selectedTab {
                postScrollToTop()
            }
            selectedTabRaw = newTab.rawValue
        }
    }

    private var userMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            UserMenuButton(
                onDownloads: { showDownloads = true },
                onSettings: { showSettings = true }
            )
        }
    }
}
#endif
