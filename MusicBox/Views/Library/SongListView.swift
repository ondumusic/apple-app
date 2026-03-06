import SwiftUI

struct SongListView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerService.self) private var player

    @State private var scrollTarget: Int?

    /// All loaded tracks in order, for building the play queue.
    private var loadedTracks: [Track] {
        library.tracks.items.compactMap { $0 }
    }

    var body: some View {
        let list = library.tracks
        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    // Play All / Shuffle buttons
                    if !loadedTracks.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                let tracks = loadedTracks
                                let items = tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                                player.playNow(queue: items)
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                let tracks = loadedTracks
                                let items = tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                                player.playShuffled(queue: items)
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

                    ForEach(list.identifiableItems) { item in
                        if let track = item.value {
                            TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                                let tracks = loadedTracks
                                let items = tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                                if let idx = items.firstIndex(where: { $0.track.id == track.id }) {
                                    player.playNow(queue: items, startingAt: idx)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 36))
                            .id(item.index)
                            .onAppear { list.itemAppeared(at: item.index) }
                        } else {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 140, height: 14)
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 80, height: 12)
                                }
                                Spacer()
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 36, height: 14)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 36))
                            .id(item.index)
                            .onAppear { list.itemAppeared(at: item.index) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
                .onChange(of: scrollTarget) { _, target in
                    if let target {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }

            SectionIndexBar(
                letterMap: buildLetterMap(from: list.identifiableItems),
                onSelect: { scrollTarget = $0 }
            )
        }
        .navigationTitle("Songs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            library.tracks.loadInitialIfNeeded()
        }
        .onChange(of: library.tracks.totalPages) {
            library.tracks.loadAllPages()
        }
        .overlay {
            if let error = library.tracks.error, library.tracks.isEmpty {
                ContentUnavailableView {
                    Label("Unable to Load Songs", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            }
        }
    }

    private func buildLetterMap(from items: [PaginatedItem<Track>]) -> [String: Int] {
        var map: [String: Int] = [:]
        for item in items {
            guard let track = item.value else { continue }
            let first = track.artist.name.prefix(1).uppercased()
            let letter = first.first?.isLetter == true ? first : "#"
            if map[letter] == nil {
                map[letter] = item.index
            }
        }
        return map
    }
}

// MARK: - Section Index Bar

private struct SectionIndexBar: View {
    static let alphabet = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .map { String(UnicodeScalar($0)!) }

    let letterMap: [String: Int]
    let onSelect: (Int) -> Void

    @State private var activeIndex: Int?

    private let letters = SectionIndexBar.alphabet

    private static let letterSize: CGFloat = 11

    var body: some View {
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
                    if let target = nearestTarget(for: i) {
                        onSelect(target)
                    }
                }
                .onEnded { _ in
                    activeIndex = nil
                }
        )
        .frame(width: 16, height: totalHeight)
        .padding(.trailing, 2)
    }

    private func nearestTarget(for i: Int) -> Int? {
        for offset in 0...i {
            let letter = letters[i - offset]
            if let target = letterMap[letter] {
                return target
            }
        }
        for j in (i + 1)..<letters.count {
            if let target = letterMap[letters[j]] {
                return target
            }
        }
        return nil
    }
}

