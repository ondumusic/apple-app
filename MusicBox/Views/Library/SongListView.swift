import SwiftUI

struct SongListView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerService.self) private var player

    var body: some View {
        let list = library.tracks
        List(list.identifiableItems) { item in
            if let track = item.value {
                TrackRow(track: track, showArtist: true, showNumber: false) {
                    player.playNow(tracks: [track])
                }
                .onAppear { list.itemAppeared(at: item.index) }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 140, height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 80, height: 12)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 36, height: 14)
                }
                .onAppear { list.itemAppeared(at: item.index) }
            }
        }
        .navigationTitle("Songs")
        .onAppear { list.loadInitialIfNeeded() }
        .overlay {
            if let error = list.error, list.isEmpty {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}
