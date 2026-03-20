import SwiftUI

struct ArtistListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SyncService.self) private var syncService
    @State private var scrollPosition = ScrollPosition()

    @AppStorage("libraryFilter") private var filterOption: LibraryFilter = .all

    @State private var artists: [Artist] = []
    @State private var hasLoaded = false

    var body: some View {
        List(artists) { artist in
            NavigationLink(value: artist) {
                ArtistCard(artist: artist)
            }
            .contextMenu {
                ArtistContextMenuItems(artist: artist)
            }
        }
        .scrollPosition($scrollPosition)
        .refreshable { await syncService.sync() }
        .navigationTitle("Artists")
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                filterMenu
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if hasLoaded && artists.isEmpty {
                if filterOption == .downloaded {
                    ContentUnavailableView("No Downloaded Artists", systemImage: "music.mic")
                } else {
                    ContentUnavailableView("No Artists", systemImage: "music.mic")
                }
            }
        }
        .task(id: musicLibrary.revision) {
            if hasLoaded {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            reloadArtists()
            hasLoaded = true
        }
        .onChange(of: filterOption) {
            reloadArtists()
        }
    }

    private func reloadArtists() {
        artists = filterOption == .downloaded
            ? musicLibrary.downloadedArtists()
            : musicLibrary.allArtists()
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $filterOption) {
                Text("All Music").tag(LibraryFilter.all)
                Text("Downloaded").tag(LibraryFilter.downloaded)
            }
        } label: {
            Label("Filter", systemImage: filterOption == .downloaded ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}
