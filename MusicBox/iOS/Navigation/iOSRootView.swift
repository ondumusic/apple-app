import SwiftUI

nonisolated enum iOSTab: String, Hashable, Sendable {
    case artists, albums, songs, downloads
}

extension Notification.Name {
    static let scrollToTop = Notification.Name("MusicBox.scrollToTop")
}

struct iOSRootView: View {
    @Environment(DownloadService.self) private var downloadService
    @State private var showSettings = false
    @State private var selectedTab: iOSTab = .artists

    private var downloadCount: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
    }

    private func postScrollToTop() {
        NotificationCenter.default.post(name: .scrollToTop, object: nil)
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Artists", systemImage: "music.mic", value: .artists) {
                NavigationStack {
                    ArtistListView()
                        .toolbar { settingsButton }
                        #if os(iOS)
                        .onNavigationBarTap { postScrollToTop() }
                        #endif
                }
                .nowPlayingBar()
            }

            Tab("Albums", systemImage: "square.stack", value: .albums) {
                NavigationStack {
                    AlbumListView()
                        .toolbar { settingsButton }
                        #if os(iOS)
                        .onNavigationBarTap { postScrollToTop() }
                        #endif
                }
                .nowPlayingBar()
            }

            Tab("Songs", systemImage: "music.note", value: .songs) {
                NavigationStack {
                    SongListView()
                        .toolbar { settingsButton }
                        #if os(iOS)
                        .onNavigationBarTap { postScrollToTop() }
                        #endif
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
        ToolbarItem(placement: .automatic) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
}
