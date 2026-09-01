#if os(macOS)
import SwiftUI

struct DownloadsViewMac: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService

    @State private var entries: [DownloadedAlbumEntry] = []
    @State private var selection: Set<UUID> = []
    @State private var totalSize: Int64 = 0
    @State private var pendingRemoval: [Album] = []
    @State private var showRemoveAllConfirmation = false

    private var isTransferring: Bool {
        !downloadService.activeDownloads.isEmpty
            || !downloadService.pendingQueue.isEmpty
            || !downloadService.failedDownloads.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isTransferring {
                DownloadTransfersSection()
                Divider()
            }
            if entries.isEmpty && !isTransferring {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Albums you download are kept on this Mac and play offline.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DownloadsTable(
                    entries: entries,
                    selection: $selection,
                    accent: settings.resolvedAccentColor,
                    onOpen: { NotificationCenter.default.post(name: .navigateToAlbum, object: $0) },
                    onPlay: playAlbum,
                    onRemove: { pendingRemoval = $0 }
                )
            }
        }
        .navigationTitle("Downloads")
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) { reload() }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { !pendingRemoval.isEmpty },
                                 set: { if !$0 { pendingRemoval = [] } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                for album in pendingRemoval { musicLibrary.markAlbumUndownloaded(albumId: album.id) }
                pendingRemoval = []
                selection = []
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("The files are deleted from this Mac. Everything stays in your library and can be downloaded again.")
        }
        .confirmationDialog(
            "Remove All Downloads?",
            isPresented: $showRemoveAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                musicLibrary.markAllUndownloaded()
                selection = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every downloaded file is deleted from this Mac. Your library is unchanged.")
        }
    }

    private var removalTitle: String {
        pendingRemoval.count == 1
            ? "Remove “\(pendingRemoval[0].name)”?"
            : "Remove \(pendingRemoval.count) Albums?"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Downloads")
                .font(.title3.weight(.semibold))
            Text("^[\(entries.count) album](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if totalSize > 0 {
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            if !entries.isEmpty {
                Button("Remove All") { showRemoveAllConfirmation = true }
                    .buttonStyle(.link)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func reload() {
        entries = musicLibrary.downloadedAlbumEntries()
        totalSize = entries.reduce(0) { $0 + $1.size }
        selection = selection.filter { id in entries.contains { $0.id == id } }
    }

    private func playAlbum(_ album: Album) {
        let tracks = musicLibrary.tracksForAlbum(album.id)
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !queue.isEmpty else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: 0) }
    }
}

/// In-flight, queued and failed downloads. A compact strip above the library list —
/// transfers are transient and shouldn't take the weight of the page.
private struct DownloadTransfersSection: View {
    @Environment(DownloadService.self) private var downloadService

    private var activeCount: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Transfers")
                    .font(.subheadline.weight(.semibold))
                if activeCount > 0 {
                    Text("^[\(activeCount) item](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if !downloadService.failedDownloads.isEmpty {
                    Button("Retry All") {
                        for failed in downloadService.failedDownloads {
                            downloadService.retryDownload(failed)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.subheadline)
                    Button("Clear Failed") { downloadService.clearFailedDownloads() }
                        .buttonStyle(.link)
                        .font(.subheadline)
                }
            }

            ForEach(downloadService.activeDownloadOrder, id: \.self) { trackId in
                if let state = downloadService.activeDownloads[trackId] {
                    transferRow(
                        title: state.trackName,
                        subtitle: state.artistName,
                        progress: state.isPaused ? nil : downloadService.progressSnapshot[trackId],
                        trailing: state.isPaused ? "Paused" : nil
                    )
                    .contextMenu {
                        if state.isPaused {
                            Button("Resume") { downloadService.resumeDownload(trackId: trackId) }
                        } else {
                            Button("Pause") { downloadService.pauseDownload(trackId: trackId) }
                        }
                        Button("Cancel", role: .destructive) {
                            downloadService.cancelDownload(trackId: trackId)
                        }
                    }
                }
            }

            ForEach(Array(downloadService.pendingQueue.prefix(4)), id: \.track.id) { info in
                transferRow(title: info.track.name, subtitle: info.track.artist.name,
                            progress: nil, trailing: "Queued")
            }
            if downloadService.pendingQueue.count > 4 {
                Text("^[\(downloadService.pendingQueue.count - 4) more queued](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(downloadService.failedDownloads) { failed in
                transferRow(title: failed.trackName, subtitle: failed.artistName,
                            progress: nil, trailing: failed.reason, isError: true)
                    .contextMenu {
                        Button("Retry") { downloadService.retryDownload(failed) }
                        Button("Dismiss", role: .destructive) {
                            downloadService.dismissFailedDownload(failed)
                        }
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func transferRow(title: String, subtitle: String, progress: Double?,
                             trailing: String?, isError: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let progress, progress > 0 {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            } else if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .font(.callout)
    }
}
#endif
