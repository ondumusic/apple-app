#if os(macOS)
import SwiftUI

struct ArtistsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary

    @State private var artists: [Artist] = []
    @State private var selectedArtistId: Artist.ID?

    var body: some View {
        NavigationSplitView {
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
                    .padding(.vertical, 1)
                    .tag(artist.id as Artist.ID?)
                }
            }
            .listStyle(.inset)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            if let id = selectedArtistId, let artist = artists.first(where: { $0.id == id }) {
                ArtistDetailMac(artist: artist)
                    .id(artist.id)
            } else {
                ContentUnavailableView("Select an Artist", systemImage: "music.mic")
            }
        }
        .navigationSplitViewStyle(.balanced)
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
