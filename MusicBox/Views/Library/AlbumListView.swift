import SwiftUI

nonisolated enum AlbumSortOption: String, CaseIterable {
    case artist = "Artist"
    case dateAdded = "Date Added"
    case name = "Name"

    var ascendingLabel: String {
        switch self {
        case .artist, .name: "A–Z"
        case .dateAdded: "Oldest First"
        }
    }

    var descendingLabel: String {
        switch self {
        case .artist, .name: "Z–A"
        case .dateAdded: "Newest First"
        }
    }
}

nonisolated enum LibraryFilter: String {
    case all = "All"
    case downloaded = "Downloaded"
}

struct AlbumListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SyncService.self) private var syncService
    @State private var scrollPosition = ScrollPosition()

    @AppStorage("albumListSort") private var sortOption: AlbumSortOption = .artist
    @AppStorage("albumListSortAscending") private var sortAscending: Bool = true
    @AppStorage("libraryFilter") private var filterOption: LibraryFilter = .all

    @State private var albums: [Album] = []
    @State private var hasLoaded = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AlbumContextMenuItems(album: album)
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
            ToolbarItem(placement: .automatic) {
                toolbarMenu
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if hasLoaded && albums.isEmpty {
                if filterOption == .downloaded {
                    ContentUnavailableView("No Downloaded Albums", systemImage: "square.stack")
                } else {
                    ContentUnavailableView("No Albums", systemImage: "square.stack")
                }
            }
        }
        .task(id: musicLibrary.revision) {
            if hasLoaded {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            reloadAlbums()
            hasLoaded = true
        }
        .onChange(of: filterOption) {
            reloadAlbums()
        }
        .onChange(of: sortOption) {
            reloadAlbums()
        }
        .onChange(of: sortAscending) {
            reloadAlbums()
        }
    }

    private func reloadAlbums() {
        let source = filterOption == .downloaded
            ? musicLibrary.downloadedAlbums()
            : musicLibrary.allAlbums()
        albums = sortedAlbums(source)
    }

    // MARK: - Toolbar Menu

    private var toolbarMenu: some View {
        Menu {
            Section("Filter") {
                Picker("Filter", selection: $filterOption) {
                    Text("All Music").tag(LibraryFilter.all)
                    Text("Downloaded").tag(LibraryFilter.downloaded)
                }
            }

            ForEach(AlbumSortOption.allCases, id: \.self) { option in
                let isActive = sortOption == option
                Toggle(isOn: Binding(
                    get: { isActive },
                    set: { _ in
                        if isActive {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = option != .dateAdded
                        }
                    }
                )) {
                    Text(option.rawValue)
                    if isActive {
                        Text(sortAscending ? option.ascendingLabel : option.descendingLabel)
                    }
                }
            }
        } label: {
            Label("Options", systemImage: filterOption == .downloaded ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Sort

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
extension LibraryFilter: RawRepresentable {}
