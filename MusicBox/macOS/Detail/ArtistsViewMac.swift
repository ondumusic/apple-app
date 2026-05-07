#if os(macOS)
import SwiftUI

struct ArtistsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary

    @State private var artists: [Artist] = []

    var body: some View {
        List {
            ForEach(artists) { artist in
                NavigationLink(value: artist) {
                    HStack(spacing: 10) {
                        Image(systemName: "music.mic")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(artist.name)
                                .lineLimit(1)
                            if let count = artist.albumCount {
                                Text("^[\(count) album](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.inset)
        .navigationTitle("Artists")
        .onChange(of: musicLibrary.revision, initial: true) {
            artists = musicLibrary.allArtists()
        }
    }
}
#endif
