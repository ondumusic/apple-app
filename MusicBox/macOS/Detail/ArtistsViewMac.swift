#if os(macOS)
import SwiftUI

struct ArtistsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary

    @State private var artists: [Artist] = []
    @State private var selectedArtistId: Artist.ID?

    var body: some View {
        // Plain HStack with a manual divider — HSplitView was rendering above the
        // window toolbar (it doesn't respect the parent's toolbar safe area), and the
        // nested NavigationSplitView had its own grey chrome problem. A regular HStack
        // sits cleanly inside the outer detail column.
        HStack(spacing: 0) {
            List(selection: $selectedArtistId) {
                ForEach(artists) { artist in
                    HStack(spacing: 8) {
                        Image(systemName: "music.mic")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                        Text(artist.name)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .tag(artist.id as Artist.ID?)
                    .contextMenu {
                        ArtistContextMenuItems(artist: artist)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.background)
            .frame(width: 240)

            Divider()

            Group {
                if let id = selectedArtistId, let artist = artists.first(where: { $0.id == id }) {
                    ArtistDetailMac(artist: artist)
                        .id(artist.id)
                } else {
                    ContentUnavailableView("Select an Artist", systemImage: "music.mic")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: musicLibrary.revision, initial: true) {
            artists = musicLibrary.allArtists()
            if selectedArtistId == nil {
                selectedArtistId = artists.first?.id
            } else if !artists.contains(where: { $0.id == selectedArtistId }) {
                selectedArtistId = artists.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artist = notification.object as? Artist else { return }
            selectedArtistId = artist.id
        }
    }
}
#endif
