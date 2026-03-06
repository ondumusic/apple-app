import SwiftUI

struct SongListView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player

    @State private var scrollTarget: UUID?

    var body: some View {
        let tracks = musicLibrary.allTracks()
        ZStack(alignment: .trailing) {
            ScrollViewReader { proxy in
                List {
                    if !tracks.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                let items = tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                                player.playNow(queue: items)
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
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

                    ForEach(tracks) { track in
                        TrackRow(track: track, showArtist: true, showArtwork: true, showNumber: false) {
                            let items = tracks.map { QueueItem(track: $0, artworkURL: $0.album?.artworkUrl) }
                            if let idx = items.firstIndex(where: { $0.track.id == track.id }) {
                                player.playNow(queue: items, startingAt: idx)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 36))
                        .id(track.id)
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
                letterMap: buildLetterMap(from: tracks),
                onSelect: { scrollTarget = $0 }
            )
        }
        .navigationTitle("Songs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
            }
        }
    }

    private func buildLetterMap(from tracks: [Track]) -> [String: UUID] {
        var map: [String: UUID] = [:]
        for track in tracks {
            let first = track.albumArtistSortName.prefix(1).uppercased()
            let letter = first.first?.isLetter == true ? first : "#"
            if map[letter] == nil {
                map[letter] = track.id
            }
        }
        return map
    }
}

// MARK: - Section Index Bar

private struct SectionIndexBar: View {
    static let alphabet = ["#"] + (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .map { String(UnicodeScalar($0)!) }

    let letterMap: [String: UUID]
    let onSelect: (UUID) -> Void

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

    private func nearestTarget(for i: Int) -> UUID? {
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
