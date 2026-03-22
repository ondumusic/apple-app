import SwiftUI

struct ArtistListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SyncService.self) private var syncService

    @AppStorage("libraryFilter") private var filterOption: LibraryFilter = .all

    @State private var sections: [ArtistSection] = []
    @State private var availableLetters: [String] = []
    @State private var hasLoaded = false

    private struct ArtistSection: Identifiable {
        let letter: String
        var artists: [Artist]
        var id: String { letter }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.artists) { artist in
                                ZStack(alignment: .leading) {
                                    NavigationLink(value: artist) { EmptyView() }
                                        .opacity(0)
                                    ArtistCard(artist: artist)
                                }
                                .contextMenu {
                                    ArtistContextMenuItems(artist: artist)
                                }
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 36))
                            }
                        } header: {
                            Text(section.letter)
                                .id(section.letter)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .onReceive(NotificationCenter.default.publisher(for: .scrollToSectionLetter)) { notification in
                    if let letter = notification.object as? String {
                        proxy.scrollTo(letter, anchor: .top)
                    }
                }
            }

            SectionIndexBar(letters: availableLetters)
        }
        .refreshable { await syncService.sync() }
        .navigationTitle("Artists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
        .overlay {
            if hasLoaded && sections.isEmpty {
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
        let allArtists = filterOption == .downloaded
            ? musicLibrary.downloadedArtists()
            : musicLibrary.allArtists()

        var grouped: [(letter: String, artists: [Artist])] = []
        var currentLetter = ""
        var currentArtists: [Artist] = []

        for artist in allArtists {
            let first = artist.sortName.prefix(1).uppercased()
            let letter = first.first?.isLetter == true ? first : "#"
            if letter != currentLetter {
                if !currentArtists.isEmpty {
                    grouped.append((currentLetter, currentArtists))
                }
                currentLetter = letter
                currentArtists = [artist]
            } else {
                currentArtists.append(artist)
            }
        }
        if !currentArtists.isEmpty {
            grouped.append((currentLetter, currentArtists))
        }

        sections = grouped.map { ArtistSection(letter: $0.letter, artists: $0.artists) }
        availableLetters = grouped.map(\.letter)
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
