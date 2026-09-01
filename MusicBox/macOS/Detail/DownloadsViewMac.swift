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

#endif
