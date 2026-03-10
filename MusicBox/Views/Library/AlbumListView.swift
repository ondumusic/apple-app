import SwiftUI

nonisolated enum AlbumSortOption: String, CaseIterable {
    case artist = "Artist"
    case dateAdded = "Date Added"
    case name = "Name"
}

struct AlbumListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(SyncService.self) private var syncService
    @Environment(NetworkMonitor.self) private var network
    @State private var scrollPosition = ScrollPosition()

    @AppStorage("albumListSort") private var sortOption: AlbumSortOption = .artist
    @AppStorage("albumListSortAscending") private var sortAscending: Bool = true

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        let albums = sortedAlbums(musicLibrary.allAlbums())
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            let tracks = musicLibrary.availableTracks(musicLibrary.tracksForAlbum(album.id), isOnline: network.isOnline)
                            guard !tracks.isEmpty else { return }
                            player.playNext(tracks: tracks, artworkURL: album.artworkUrl)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }

                        Button {
                            let tracks = musicLibrary.availableTracks(musicLibrary.tracksForAlbum(album.id), isOnline: network.isOnline)
                            guard !tracks.isEmpty else { return }
                            player.addToEnd(tracks: tracks, artworkURL: album.artworkUrl)
                        } label: {
                            Label("Add to Queue", systemImage: "text.append")
                        }

                        Divider()

                        if musicLibrary.isAlbumDownloaded(albumId: album.id) {
                            Button(role: .destructive) {
                                musicLibrary.markAlbumUndownloaded(albumId: album.id)
                            } label: {
                                Label("Remove Download", systemImage: "trash")
                            }
                        } else {
                            Button {
                                guard let fullAlbum = musicLibrary.albumWithTracks(album.id),
                                      let artistObj = musicLibrary.artist(album.artistId) else { return }
                                downloadService.download(album: fullAlbum, artist: artistObj)
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .scrollPosition($scrollPosition)
        .refreshable { await syncService.sync() }
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            }
        }
    }

    // MARK: - Sort

    private var sortMenu: some View {
        Menu {
            ForEach(AlbumSortOption.allCases, id: \.self) { option in
                Button {
                    if sortOption == option {
                        sortAscending.toggle()
                    } else {
                        sortOption = option
                        sortAscending = option != .dateAdded // date added defaults descending (newest first)
                    }
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private func sortedAlbums(_ albums: [Album]) -> [Album] {
        albums.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .artist:
                let aName = a.artistSortName ?? ""
                let bName = b.artistSortName ?? ""
                if aName != bName {
                    result = aName.localizedStandardCompare(bName) == .orderedAscending
                } else {
                    let aYear = a.releaseYear ?? 0
                    let bYear = b.releaseYear ?? 0
                    if aYear != bYear {
                        result = aYear > bYear
                    } else {
                        result = a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
                    }
                }
            case .dateAdded:
                let aDate = a.insertedAt ?? .distantPast
                let bDate = b.insertedAt ?? .distantPast
                if aDate != bDate {
                    result = aDate < bDate
                } else {
                    result = a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
                }
            case .name:
                result = a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
            }
            return sortAscending ? result : !result
        }
    }
}

extension AlbumSortOption: RawRepresentable {}
