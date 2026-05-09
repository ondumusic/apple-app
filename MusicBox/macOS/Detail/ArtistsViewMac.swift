#if os(macOS)
import SwiftUI

struct ArtistsViewMac: View {
    /// When non-nil, the master list selects this artist on first load instead of
    /// defaulting to artists.first. MacOSContentView sets it from .navigateToArtist
    /// so opening this view from "Go to Artist" lands directly on the right artist
    /// without flickering through the default first-artist selection.
    @Binding var pendingArtistSelection: UUID?

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
            // Prefer a pending navigation request, then keep current, then fall back
            // to the first artist. The pending value is consumed once.
            if let pending = pendingArtistSelection, artists.contains(where: { $0.id == pending }) {
                selectedArtistId = pending
                pendingArtistSelection = nil
            } else if selectedArtistId == nil || !artists.contains(where: { $0.id == selectedArtistId }) {
                selectedArtistId = artists.first?.id
            }
        }
        .onChange(of: pendingArtistSelection) { _, newValue in
            // Late navigation while ArtistsViewMac is already onscreen.
            if let id = newValue, artists.contains(where: { $0.id == id }) {
                selectedArtistId = id
                pendingArtistSelection = nil
            }
        }
    }
}
#endif
