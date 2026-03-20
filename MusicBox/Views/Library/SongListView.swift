import SwiftUI

struct SongListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(SyncService.self) private var syncService
    @Environment(NetworkMonitor.self) private var network

    @AppStorage("libraryFilter") private var filterOption: LibraryFilter = .all

    @State private var sections: [SongSection] = []
    @State private var allQueueItems: [QueueItem] = []
    @State private var availableLetters: [String] = []
    @State private var hasLoaded = false

    private struct SongSection: Identifiable {
        let letter: String
        var tracks: [Track]
        var id: String { letter }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    if !sections.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                let available = musicLibrary.availableItems(allQueueItems, isOnline: network.isOnline)
                                guard !available.isEmpty else { return }
                                player.requestPlay { player.playNow(queue: available) }
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                            }

                            Button {
                                let available = musicLibrary.availableItems(allQueueItems, isOnline: network.isOnline)
                                guard !available.isEmpty else { return }
                                player.requestPlay { player.playShuffled(queue: available) }
                            } label: {
                                Label("Shuffle All", systemImage: "shuffle")
                            }
                        }
                        .buttonStyle(PillButtonStyle())
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 36))
                        .listRowSeparator(.hidden)
                    }

                    ForEach(sections) { section in
                        Section {
                            ForEach(section.tracks) { track in
                                TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                                    let available = musicLibrary.availableItems(allQueueItems, isOnline: network.isOnline)
                                    if let idx = available.firstIndex(where: { $0.track.id == track.id }) {
                                        player.requestPlay { player.playNow(queue: available, startingAt: idx) }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 36))
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

            SectionIndexBar(
                letters: availableLetters
            )
        }
        .refreshable { await syncService.sync() }
        .navigationTitle("Songs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                filterMenu
            }
        }
        .overlay {
            if hasLoaded && sections.isEmpty {
                if filterOption == .downloaded {
                    ContentUnavailableView("No Downloaded Songs", systemImage: "music.note")
                } else {
                    ContentUnavailableView("No Songs", systemImage: "music.note")
                }
            }
        }
        .task(id: musicLibrary.revision) {
            if hasLoaded {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            reloadTracks()
            hasLoaded = true
        }
        .onChange(of: musicLibrary.downloadChanged) {
            for i in sections.indices {
                musicLibrary.applyDownloadChanges(to: &sections[i].tracks)
            }
        }
        .onChange(of: filterOption) {
            reloadTracks()
        }
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

    private func reloadTracks() {
        let allTracks = filterOption == .downloaded
            ? musicLibrary.downloadedTracks()
            : musicLibrary.allTracks()
        var grouped: [(letter: String, tracks: [Track])] = []
        var currentLetter = ""
        var currentTracks: [Track] = []

        for track in allTracks {
            let first = track.albumArtistSortName.prefix(1).uppercased()
            let letter = first.first?.isLetter == true ? first : "#"
            if letter != currentLetter {
                if !currentTracks.isEmpty {
                    grouped.append((currentLetter, currentTracks))
                }
                currentLetter = letter
                currentTracks = [track]
            } else {
                currentTracks.append(track)
            }
        }
        if !currentTracks.isEmpty {
            grouped.append((currentLetter, currentTracks))
        }

        sections = grouped.map { SongSection(letter: $0.letter, tracks: $0.tracks) }
        availableLetters = grouped.map(\.letter)
        allQueueItems = allTracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
    }
}

extension Notification.Name {
    static let scrollToSectionLetter = Notification.Name("scrollToSectionLetter")
}
