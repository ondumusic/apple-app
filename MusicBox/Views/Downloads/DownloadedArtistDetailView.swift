import SwiftUI

struct DownloadedArtistDetailView: View {
    @Environment(OfflineStore.self) private var offlineStore

    let artist: DownloadedArtist
    @State private var albumToDelete: DownloadedAlbum?

    var body: some View {
        List {
            ForEach(artist.albums.sorted(by: { ($0.releaseYear ?? 0) < ($1.releaseYear ?? 0) })) { album in
                NavigationLink(value: album) {
                    HStack(spacing: 12) {
                        ArtworkView(url: album.artworkUrl)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.name)
                                .lineLimit(1)

                            if let year = album.releaseYear {
                                Text(String(year))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("\(album.tracks.count) \(album.tracks.count == 1 ? "song" : "songs")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        albumToDelete = album
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        albumToDelete = album
                    } label: {
                        Label("Delete Album", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: DownloadedAlbum.self) { album in
            DownloadedAlbumDetailView(album: album)
        }
        .confirmationDialog(
            "Delete Album",
            isPresented: Binding(get: { albumToDelete != nil }, set: { if !$0 { albumToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let album = albumToDelete {
                    offlineStore.deleteAlbum(albumId: album.id)
                }
            }
        } message: {
            if let album = albumToDelete {
                Text("Remove the downloaded album \"\(album.name)\"?")
            }
        }
    }
}
