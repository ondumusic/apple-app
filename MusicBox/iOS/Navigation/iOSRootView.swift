import SwiftUI

struct iOSRootView: View {
    @State private var showSettings = false

    var body: some View {
        TabView {
            Tab("Artists", systemImage: "music.mic") {
                NavigationStack {
                    ArtistListView()
                        .toolbar { settingsButton }
                }
            }

            Tab("Albums", systemImage: "square.stack") {
                NavigationStack {
                    AlbumListView()
                        .toolbar { settingsButton }
                }
            }

            Tab("Songs", systemImage: "music.note") {
                NavigationStack {
                    SongListView()
                        .toolbar { settingsButton }
                }
            }
        }
        .nowPlayingBar()
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
