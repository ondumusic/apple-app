import SwiftUI

nonisolated enum AlbumSortOption: String, CaseIterable {
    case artist = "Artist"
    case dateAdded = "Date Added"
    case name = "Name"
    case releaseYear = "Release Year"
    case plays = "Plays"
    case lastPlayed = "Last Played"

    /// What this ordering means by default. Nobody picks "Date Added" wanting the oldest
    /// record they own first, and nobody picks "Name" wanting Z.
    var defaultAscending: Bool {
        switch self {
        case .artist, .name: true
        case .dateAdded, .releaseYear, .plays, .lastPlayed: false
        }
    }

    var ascendingLabel: String {
        switch self {
        case .artist, .name: "A–Z"
        case .dateAdded: "Oldest First"
        case .releaseYear: "Oldest First"
        case .plays: "Least Played"
        case .lastPlayed: "Longest Ago"
        }
    }

    var descendingLabel: String {
        switch self {
        case .artist, .name: "Z–A"
        case .dateAdded: "Newest First"
        case .releaseYear: "Newest First"
        case .plays: "Most Played"
        case .lastPlayed: "Most Recent"
        }
    }

    /// Only these two need the aggregate, which costs a pass over every played track.
    var needsPlayStats: Bool {
        switch self {
        case .plays, .lastPlayed: true
        default: false
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
            // Matches macOS: the ordering carries its own direction, and both platforms
            // share the persisted setting.
            sortAscending = sortOption.defaultAscending
            reloadAlbums()
        }
        .onChange(of: sortAscending) {
            reloadAlbums()
        }
    }

    private func reloadAlbums() {
        let source =
            filterOption == .downloaded
            ? musicLibrary.downloadedAlbums()
            : musicLibrary.allAlbums()
        albums = sortOption.sorted(source, ascending: sortAscending, playStats: playStats())
    }

    /// Skipped unless the chosen sort needs it: it's a pass over every played track.
    private func playStats() -> [UUID: MusicLibrary.AlbumPlayStats] {
        sortOption.needsPlayStats ? musicLibrary.albumPlayStats() : [:]
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
                Toggle(
                    isOn: Binding(
                        get: { isActive },
                        set: { _ in
                            if isActive {
                                sortAscending.toggle()
                            } else {
                                sortOption = option
                                sortAscending = option != .dateAdded && option != .releaseYear
                            }
                        }
                    )
                ) {
                    Text(option.rawValue)
                    if isActive {
                        Text(sortAscending ? option.ascendingLabel : option.descendingLabel)
                    }
                }
            }
        } label: {
            Label(
                "Options",
                systemImage: filterOption == .downloaded
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Sort

}

extension AlbumSortOption {
    /// Shared with the macOS grid so both platforms order albums identically.
    func sorted(
        _ albums: [Album], ascending: Bool,
        playStats: [UUID: MusicLibrary.AlbumPlayStats] = [:]
    ) -> [Album] {
        albums.sorted { a, b in
            let result: Bool
            switch self {
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
            case .releaseYear:
                let aYear = a.releaseYear ?? 0
                let bYear = b.releaseYear ?? 0
                if aYear != bYear {
                    result = aYear < bYear
                } else {
                    result = a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
                }
            case .plays:
                let aPlays = playStats[a.id]?.playCount ?? 0
                let bPlays = playStats[b.id]?.playCount ?? 0
                if aPlays != bPlays {
                    result = aPlays < bPlays
                } else {
                    // Same count, so the one played more recently is the better answer —
                    // reversed here because the caller flips the whole comparison for a
                    // descending sort, and this tiebreak means newest-first either way.
                    let aPlayed = playStats[a.id]?.lastPlayedAt ?? .distantPast
                    let bPlayed = playStats[b.id]?.lastPlayedAt ?? .distantPast
                    if aPlayed != bPlayed {
                        result = aPlayed < bPlayed
                    } else {
                        result = a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
                    }
                }
            case .lastPlayed:
                // Never played is longest ago, so descending leaves it at the bottom
                // rather than on top of everything that has been played.
                let aPlayed = playStats[a.id]?.lastPlayedAt ?? .distantPast
                let bPlayed = playStats[b.id]?.lastPlayedAt ?? .distantPast
                if aPlayed != bPlayed {
                    result = aPlayed < bPlayed
                } else {
                    result = a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
                }
            }
            return ascending ? result : !result
        }
    }
}

extension AlbumSortOption: RawRepresentable {}
extension LibraryFilter: RawRepresentable {}
