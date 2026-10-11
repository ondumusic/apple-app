import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadService.self) private var downloadService
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(NetworkMonitor.self) private var network
    @State private var showDeleteAllConfirmation = false
    @State private var showDownloadAllConfirmation = false
    @State private var showAllDownloadedAlert = false
    @State private var artistToDelete: Artist?
    @State private var artists: [Artist] = []
    @State private var totalSize: Int64 = 0
    @State private var artistSizes: [UUID: Int64] = [:]
    @State private var hasLoaded = false
    @State private var isVisible = false

    var body: some View {
        List {
            if let reason = downloadPausedNotice {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if !downloadService.activeDownloads.isEmpty || !downloadService.pendingQueue.isEmpty {
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
                                    ProgressView()
                                        .controlSize(.small)
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

            if !downloadService.failedDownloads.isEmpty {
                Section {
                    ForEach(downloadService.failedDownloads) { failed in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failed.trackName)
                                    .lineLimit(1)
                                Text(failed.reason)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                downloadService.retryDownload(failed)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.callout)
                            }
                            .accessibilityLabel("Retry Download")
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                downloadService.dismissFailedDownload(failed)
                            } label: {
                                Label("Dismiss", systemImage: "xmark")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Failed")
                        Spacer()
                        if downloadService.failedDownloads.count > 1 {
                            Button("Retry All") {
                                for failed in downloadService.failedDownloads {
                                    downloadService.retryDownload(failed)
                                }
                            }
                            .font(.caption)

                            Button("Clear All") {
                                downloadService.clearFailedDownloads()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                    .textCase(nil)
                }
            }

            if hasLoaded && artists.isEmpty && downloadService.activeDownloads.isEmpty
                && downloadService.pendingQueue.isEmpty && downloadService.failedDownloads.isEmpty
            {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded music will appear here.")
                )
            } else if !artists.isEmpty {
                Section {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(artist.name)
                                    HStack(spacing: 8) {
                                        Text("^[\(artist.albumCount ?? 0) album](inflect: true)")
                                        if let size = artistSizes[artist.id], size > 0 {
                                            Text(formattedSize(size))
                                        }
                                    }
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
                                Label("Remove Downloaded Music", systemImage: "trash")
                            }
                        }
                        .confirmationDialog(
                            "Remove Downloads",
                            isPresented: Binding(
                                get: { artistToDelete?.id == artist.id },
                                set: { if !$0 { artistToDelete = nil } }
                            ),
                            titleVisibility: .visible
                        ) {
                            Button("Remove", role: .destructive) {
                                musicLibrary.markArtistUndownloaded(artistId: artist.id)
                            }
                        } message: {
                            Text(
                                "Remove all downloaded files for \(artist.name)? The artist stays in your library and can be re-downloaded."
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text("Library")
                        Spacer()
                        if totalSize > 0 {
                            Text(formattedSize(totalSize))
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        // On macOS, MacOSContentView's NavigationStack already registers Artist/Album
        // destinations — registering them again here causes a duplicate-destination
        // collision that hangs the navigation push.
        #if os(iOS)
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist, downloadedOnly: true)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album, downloadedOnly: true)
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        if downloadService.hasUndownloadedTracks(library: musicLibrary) {
                            showDownloadAllConfirmation = true
                        } else {
                            showAllDownloadedAlert = true
                        }
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
                .alert("All Songs Downloaded", isPresented: $showAllDownloadedAlert) {
                    Button("OK") {}
                } message: {
                    Text("Your entire library is already downloaded.")
                }
            }
        }
        .task(id: musicLibrary.revision) {
            reloadData()
        }
        .onChange(of: musicLibrary.downloadChanged) {
            if isVisible { reloadData() }
        }
        .onAppear {
            isVisible = true
            reloadData()
        }
        .onDisappear { isVisible = false }
    }

    private func reloadData() {
        let summary = musicLibrary.downloadedSummary()
        artists = summary.artists
        totalSize = summary.totalSize
        artistSizes = summary.artistSizes
        hasLoaded = true
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var downloadPausedNotice: String? {
        let hasQueuedWork = !downloadService.activeDownloads.isEmpty || !downloadService.pendingQueue.isEmpty
        guard hasQueuedWork else { return nil }
        if let reason = downloadService.downloadsPausedReason {
            switch reason {
            case .lowPowerMode: return "Downloads paused — Low Power Mode is on"
            case .lowDiskSpace: return "Downloads paused — device storage is low"
            }
        }
        if network.isConstrained {
            return "Downloads paused — Low Data Mode is on"
        }
        return nil
    }
}
