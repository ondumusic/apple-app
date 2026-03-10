import SwiftUI

nonisolated enum iOSTab: String, Hashable, Sendable {
    case artists, albums, songs, search, downloads
}


struct iOSRootView: View {
    @Environment(AuthService.self) private var authService
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network
    @State private var showSettings = false
    @AppStorage("selectedTab") private var selectedTab: iOSTab = .artists
    @State private var artistsPath = NavigationPath()
    @State private var albumsPath = NavigationPath()
    @State private var searchText = ""

    private var downloadCount: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
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
            .padding(.vertical, 6)
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
            .padding(.vertical, 6)
            .background(.yellow)
        }

        TabView(selection: tabSelection) {
            Tab("Artists", systemImage: "music.mic", value: .artists) {
                NavigationStack(path: $artistsPath) {
                    ArtistListView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Albums", systemImage: "square.stack", value: .albums) {
                NavigationStack(path: $albumsPath) {
                    AlbumListView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Songs", systemImage: "music.note", value: .songs) {
                NavigationStack {
                    SongListView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack {
                    SearchView(query: searchText)
                        .navigationTitle("Search")
                        .searchable(text: $searchText, prompt: "Artists, albums, or songs")
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Downloads", systemImage: "arrow.down.circle", value: .downloads) {
                NavigationStack {
                    DownloadsView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }
            .badge(downloadCount > 0 ? downloadCount : 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            artistsPath = NavigationPath()
            selectedTab = .artists
            // Delay slightly so tab switch completes before push
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                artistsPath.append(artist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let album = notification.object as? Album else { return }
            albumsPath = NavigationPath()
            selectedTab = .albums
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                albumsPath.append(album)
            }
        }
        .queueConfirmationOverlay()
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
        } // VStack
    }

    private var tabSelection: Binding<iOSTab> {
        Binding {
            selectedTab
        } set: { newTab in
            if newTab == selectedTab {
                postScrollToTop()
            }
            selectedTab = newTab
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}
