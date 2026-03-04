import SwiftUI

struct iOSRootView: View {
    var body: some View {
        TabView {
            Tab("Artists", systemImage: "music.mic") {
                NavigationStack {
                    ArtistListView()
                }
            }

            Tab("Albums", systemImage: "square.stack") {
                NavigationStack {
                    AlbumListView()
                }
            }

            Tab("Songs", systemImage: "music.note") {
                NavigationStack {
                    SongListView()
                }
            }
        }
    }
}
