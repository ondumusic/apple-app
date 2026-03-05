import SwiftUI

struct iOSRootView: View {
    @Environment(DownloadService.self) private var downloadService
    @State private var showSettings = false

    private var downloadCount: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
    }

    var body: some View {
        TabView {
            Tab("Artists", systemImage: "music.mic") {
                NavigationStack {
                    ArtistListView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Albums", systemImage: "square.stack") {
                NavigationStack {
                    AlbumListView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Songs", systemImage: "music.note") {
                NavigationStack {
                    SongListView()
                        .toolbar { settingsButton }
                }
                .nowPlayingBar()
            }

            Tab("Downloads", systemImage: "arrow.down.circle") {
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
