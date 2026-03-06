import SwiftUI

struct ArtistDetailView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(OfflineStore.self) private var offlineStore
    @Environment(APIService.self) private var api

    let artist: Artist

    @State private var list: PaginatedList<Album>?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if let list {
                // Play All / Shuffle buttons
                if list.hasLoaded {
                    HStack(spacing: 12) {
                        Button {
                            playAll(shuffle: false)
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }

                        Button {
                            playAll(shuffle: true)
                        } label: {
                            Label("Shuffle All", systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(list.identifiableItems) { item in
                        if let album = item.value {
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task {
                                        guard let full = try? await api.fetchAlbum(album.id),
                                              let tracks = full.tracks, !tracks.isEmpty else { return }
                                        player.playNext(tracks: tracks, artworkURL: full.artworkUrl)
                                    }
                                } label: {
                                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                }

                                Button {
                                    Task {
                                        guard let full = try? await api.fetchAlbum(album.id),
                                              let tracks = full.tracks, !tracks.isEmpty else { return }
                                        player.addToEnd(tracks: tracks, artworkURL: full.artworkUrl)
                                    }
                                } label: {
                                    Label("Add to Queue", systemImage: "text.append")
                                }

                                Divider()

                                if offlineStore.isAlbumDownloaded(albumId: album.id) {
                                    Button(role: .destructive) {
                                        offlineStore.deleteAlbum(albumId: album.id)
                                    } label: {
                                        Label("Remove Download", systemImage: "trash")
                                    }
                                } else {
                                    Button {
                                        Task {
                                            guard let full = try? await api.fetchAlbum(album.id),
                                                  let tracks = full.tracks,
                                                  let trackArtist = tracks.first?.artist else { return }
                                            downloadService.download(album: full, artist: trackArtist)
                                        }
                                    } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                            }
                            .onAppear { list.itemAppeared(at: item.index) }
                        } else {
                            AlbumCardPlaceholder()
                                .onAppear { list.itemAppeared(at: item.index) }
                        }
                    }
                }
                .padding()

                if let error = list.error, list.isEmpty {
                    ContentUnavailableView {
                        Label("Unable to Load Albums", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                    .padding()
                }
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(artist.name)
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .onAppear {
            if list == nil {
                let l = library.albumList(for: artist)
                list = l
                l.loadInitialIfNeeded()
            }
        }
    }

    private func playAll(shuffle: Bool) {
        Task {
            guard let albums = try? await api.fetchArtistAlbumsWithTracks(artistId: artist.id) else { return }
            let items = albums.flatMap { album in
                (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
            }
            guard !items.isEmpty else { return }
            if shuffle {
                player.playShuffled(queue: items)
            } else {
                player.playNow(queue: items)
            }
        }
    }
}
