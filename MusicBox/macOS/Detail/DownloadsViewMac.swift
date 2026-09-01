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

    /// Columns, not a run-on HStack: the artist used to start at a different x on every
    /// row and the status floated at the far right, disconnected from what it described.
    private static let artistWidth: CGFloat = 200
    private static let statusWidth: CGFloat = 140
    /// Enough to see what's happening without the strip taking over the page.
    private static let visibleRows = 5

    private struct Row: Identifiable {
        let id: UUID
        let title: String
        let artist: String
        let progress: Double?
        let status: String?
        let isError: Bool
        let menu: AnyView
    }

    private var rows: [Row] {
        var all: [Row] = []
        for trackId in downloadService.activeDownloadOrder {
            guard let state = downloadService.activeDownloads[trackId] else { continue }
            all.append(Row(
                id: trackId, title: state.trackName, artist: state.artistName,
                progress: state.isPaused ? nil : downloadService.progressSnapshot[trackId],
                status: state.isPaused ? "Paused" : nil, isError: false,
                menu: AnyView(activeMenu(trackId: trackId, isPaused: state.isPaused))
            ))
        }
        for info in downloadService.pendingQueue {
            all.append(Row(id: info.track.id, title: info.track.name,
                           artist: info.track.artist.name, progress: nil,
                           status: "Queued", isError: false, menu: AnyView(EmptyView())))
        }
        for failed in downloadService.failedDownloads {
            all.append(Row(id: failed.id, title: failed.trackName, artist: failed.artistName,
                           progress: nil, status: failed.reason, isError: true,
                           menu: AnyView(failedMenu(failed))))
        }
        return all
    }

    var body: some View {
        let all = rows
        let shown = all.prefix(Self.visibleRows)
        VStack(alignment: .leading, spacing: 6) {
            header(total: all.count)
            ForEach(Array(shown)) { row in
                transferRow(row).contextMenu { row.menu }
            }
            if all.count > shown.count {
                Text("^[\(all.count - shown.count) more](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func header(total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Transfers")
                .font(.subheadline.weight(.semibold))
            Text("^[\(total) item](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        .padding(.bottom, 2)
    }

    private func transferRow(_ row: Row) -> some View {
        HStack(spacing: 12) {
            Text(row.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.artist)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.artistWidth, alignment: .leading)
            status(row)
                .frame(width: Self.statusWidth, alignment: .trailing)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func status(_ row: Row) -> some View {
        if let progress = row.progress, progress > 0 {
            HStack(spacing: 8) {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
        } else if let status = row.status {
            Text(status)
                .font(.caption)
                .foregroundStyle(row.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        } else {
            // Starting: an indeterminate bar keeps the column the same shape as a
            // determinate one, so rows don't jump as downloads get going.
            ProgressView().progressViewStyle(.linear)
        }
    }

    private func activeMenu(trackId: UUID, isPaused: Bool) -> some View {
        Group {
            if isPaused {
                Button("Resume") { downloadService.resumeDownload(trackId: trackId) }
            } else {
                Button("Pause") { downloadService.pauseDownload(trackId: trackId) }
            }
            Button("Cancel", role: .destructive) { downloadService.cancelDownload(trackId: trackId) }
        }
    }

    private func failedMenu(_ failed: DownloadService.FailedDownload) -> some View {
        Group {
            Button("Retry") { downloadService.retryDownload(failed) }
            Button("Dismiss", role: .destructive) { downloadService.dismissFailedDownload(failed) }
        }
    }
}
#endif
