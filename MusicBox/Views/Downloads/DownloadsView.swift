import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadService.self) private var downloadService
    @Environment(MusicLibrary.self) private var musicLibrary
    @State private var showDeleteAllConfirmation = false
    @State private var showDownloadAllConfirmation = false
    @State private var artistToDelete: Artist?
    @State private var artists: [Artist] = []

    var body: some View {
        List {
            if downloadService.hasActivity {
                Section {
                    // All downloads (active + queued in URLSession)
                    ForEach(downloadService.activeDownloadOrder, id: \.self) { trackId in
                        if let state = downloadService.activeDownloads[trackId] {
                            let progress = downloadService.progressSnapshot[trackId] ?? 0

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(state.trackName)
                                        .lineLimit(1)
                                    Text(state.artistName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if state.isPaused {
                                    Text("Paused")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if progress > 0 {
                                    ProgressView(value: progress)
                                        .frame(width: 60)

                                    Text("\(Int(progress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                        .frame(width: 34, alignment: .trailing)
                                } else {
                                    Text("Waiting\u{2026}")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                if state.isPaused {
                                    Button {
                                        downloadService.resumeDownload(trackId: trackId)
                                    } label: {
                                        Label("Resume", systemImage: "play.circle")
                                    }
                                } else {
                                    Button {
                                        downloadService.pauseDownload(trackId: trackId)
                                    } label: {
                                        Label("Pause", systemImage: "pause.circle")
                                    }
                                }

                                Button(role: .destructive) {
                                    downloadService.cancelDownload(trackId: trackId)
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }

                    // Pending queue
                    ForEach(downloadService.pendingQueue, id: \.track.id) { info in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.track.name)
                                    .lineLimit(1)
                                Text(info.artist.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text("Waiting\u{2026}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                downloadService.cancelDownload(trackId: info.track.id)
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Downloading")
                        Spacer()
                        if downloadService.isPaused {
                            Button("Resume All") {
                                downloadService.resumeAll()
                            }
                            .font(.caption)
                        } else {
                            Button("Pause All") {
                                downloadService.pauseAll()
                            }
                            .font(.caption)
                        }
                        Button("Cancel All") {
                            downloadService.cancelAll()
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    .textCase(nil)
                }
            }

            if artists.isEmpty && !downloadService.hasActivity {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded music will appear here.")
                )
            } else if !artists.isEmpty {
                Section("Library") {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            Label {
                                HStack {
                                    Text(artist.name)
                                    Spacer()
                                    Text("\(artist.albumCount ?? 0) \(artist.albumCount == 1 ? "album" : "albums")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "music.mic")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                artistToDelete = artist
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                artistToDelete = artist
                            } label: {
                                Label("Delete Artist", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist, downloadedOnly: true)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album, downloadedOnly: true)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showDownloadAllConfirmation = true
                    } label: {
                        Label("Download All", systemImage: "arrow.down.circle")
                    }

                    if !artists.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label("Remove All Downloads", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .confirmationDialog(
                    "Download All Songs",
                    isPresented: $showDownloadAllConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Download All") {
                        downloadService.downloadAll(library: musicLibrary)
                    }
                } message: {
                    Text("This will download your entire music library for offline playback.")
                }
                .confirmationDialog(
                    "Remove All Downloads",
                    isPresented: $showDeleteAllConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove All", role: .destructive) {
                        downloadService.cancelAll()
                        musicLibrary.markAllUndownloaded()
                    }
                } message: {
                    Text("This will remove all downloaded music from this device.")
                }
            }
        }
        .onChange(of: musicLibrary.revision, initial: true) {
            artists = musicLibrary.downloadedArtists()
        }
        .onChange(of: musicLibrary.downloadChanged) {
            artists = musicLibrary.downloadedArtists()
        }
        .confirmationDialog(
            "Delete Artist",
            isPresented: Binding(get: { artistToDelete != nil }, set: { if !$0 { artistToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let artist = artistToDelete {
                    musicLibrary.markArtistUndownloaded(artistId: artist.id)
                }
            }
        } message: {
            if let artist = artistToDelete {
                Text("Remove all downloaded music by \(artist.name)?")
            }
        }
    }
}
