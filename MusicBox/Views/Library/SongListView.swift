import SwiftUI

struct SongListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(SyncService.self) private var syncService

    @State private var sections: [SongSection] = []
    @State private var allQueueItems: [QueueItem] = []
    @State private var availableLetters: [String] = []

    private struct SongSection: Identifiable {
        let letter: String
        let tracks: [Track]
        var id: String { letter }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    if !sections.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                player.playNow(queue: allQueueItems)
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                player.playShuffled(queue: allQueueItems)
                            } label: {
                                Label("Shuffle All", systemImage: "shuffle")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 36))
                        .listRowSeparator(.hidden)
                    }

                    ForEach(sections) { section in
                        Section {
                            ForEach(section.tracks) { track in
                                TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                                    if let idx = allQueueItems.firstIndex(where: { $0.track.id == track.id }) {
                                        player.playNow(queue: allQueueItems, startingAt: idx)
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
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) {
            reloadTracks()
        }
    }

    private func reloadTracks() {
        let allTracks = musicLibrary.allTracks()
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

// MARK: - Section Index Bar

private struct SectionIndexBar: View {
    let letters: [String]

    @State private var activeIndex: Int?

    private static let letterSize: CGFloat = 11

    var body: some View {
        if !letters.isEmpty {
            let totalHeight = Self.letterSize * CGFloat(letters.count)

            VStack(spacing: 0) {
                ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 9.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.letterSize)
                }
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let raw = Int(value.location.y / Self.letterSize)
                        let i = Swift.max(0, Swift.min(raw, letters.count - 1))
                        guard i != activeIndex else { return }
                        activeIndex = i
                        NotificationCenter.default.post(name: .scrollToSectionLetter, object: letters[i])
                    }
                    .onEnded { _ in
                        activeIndex = nil
                    }
            )
            .frame(width: 16, height: totalHeight)
            .padding(.trailing, 2)
        }
    }
}
