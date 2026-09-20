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
    @State private var showRemoveAllConfirmation = false
    @State private var showDownloadAllConfirmation = false

    private var isTransferring: Bool {
        !downloadService.activeDownloads.isEmpty
            || !downloadService.pendingQueue.isEmpty
            || !downloadService.failedDownloads.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            DownloadPausedNotice()
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
                    onRemove: requestRemoval
                )
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: musicLibrary.downloadChanged) { reload() }
        .confirmationDialog(
            "Download Your Whole Library?",
            isPresented: $showDownloadAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download All") { downloadService.downloadAll(library: musicLibrary) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every song is downloaded to this Mac for offline playback. You can watch progress in the Activity window.")
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

    private func requestRemoval(_ albums: [Album]) {
        let ids = albums.flatMap { musicLibrary.tracksForAlbum($0.id).filter(\.isDownloaded).map(\.id) }
        let subject = albums.count == 1
            ? albums[0].name
            : String(AttributedString(localized: "^[\(albums.count) album](inflect: true)").characters)
        DownloadRemovalRequest.post(trackIds: Set(ids), subject: subject)
        selection = []
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
