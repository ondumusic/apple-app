#if os(macOS)
import SwiftUI

struct PlaylistDetailMac: View {
    let playlistId: UUID

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(PlaylistController.self) private var playlistController
    @Environment(DownloadService.self) private var downloadService

    @State private var playlist: Playlist?
    @State private var items: [PlaylistItem] = []
    @State private var tracks: [Track] = []
    @State private var selection: Set<UUID> = []
    @State private var isRenamingHeader = false
    @State private var headerNameDraft: String = ""

    private var trackActions: TrackActions {
        var a = TrackActions.standard(
            player: player,
            musicLibrary: musicLibrary,
            network: network,
            downloadService: downloadService
        )
        a.removeFromPlaylistRows = { rows in
            removeRows(rows)
        }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            TracksTable(
                tracks: tracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: true,
                showAlbum: true,
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                usesPlaylistPosition: true,
                onReorder: reorderRows(_:to:),
                onDelete: removeRows(_:),
                rowHeight: DetailPageMetrics.trackRowHeight
            )
        }
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: playlistId) {
            isRenamingHeader = false
            reload()
        }
        .onChange(of: musicLibrary.downloadChanged) {
            musicLibrary.applyDownloadChanges(to: &tracks)
        }
    }

    /// Mirrors the album header's control: a spinner while any of the playlist's tracks
    /// are in flight, a filled badge once every track is on disk, an arrow otherwise.
    private var downloadButton: some View {
        let ids = Set(tracks.map(\.id))
        let isDownloading = tracks.contains { downloadService.isDownloading(trackId: $0.id) }
        let isComplete = !tracks.isEmpty && tracks.allSatisfy(\.isDownloaded)
        return DownloadStateButton(
            state: isDownloading ? .downloading : (isComplete ? .downloaded : .notDownloaded),
            action: {
                if isComplete {
                    DownloadRemovalRequest.post(trackIds: ids, subject: playlist?.name ?? "",
                                                playlistId: playlistId)
                } else {
                    playlistController.enableAutoDownload(playlistId)
                }
            },
            isEnabled: !tracks.isEmpty && !isDownloading
        )
    }

    private var metadataParts: [String] {
        var parts = [String(AttributedString(localized: "^[\(tracks.count) song](inflect: true)").characters)]
        if totalDuration > 0 { parts.append(formattedTotalDuration(totalDuration)) }
        return parts
    }

    private var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PlaylistArtworkMosaic(tracks: tracks)
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 4) {
                if isRenamingHeader {
                    TextField("", text: $headerNameDraft)
                        .textFieldStyle(.plain)
                        .font(.largeTitle.bold())
                        .onSubmit(commitHeaderRename)
                        .onExitCommand {
                            isRenamingHeader = false
                        }
                } else {
                    Text(playlist?.name ?? "")
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            guard let p = playlist else { return }
                            headerNameDraft = p.name
                            isRenamingHeader = true
                        }
                }
                DetailMetadataLine(parts: metadataParts)
            }
            Spacer()
            HStack(spacing: 8) {
                PlayShuffleButtons(
                    accent: settings.resolvedAccentColor,
                    onPlay: { playAll(shuffle: false) },
                    onShuffle: { playAll(shuffle: true) },
                    isEnabled: !tracks.isEmpty
                )
                downloadButton
            }
        }
        .padding(.horizontal, DetailPageMetrics.horizontalInset)
        .padding(.top, DetailPageMetrics.topInset)
        .padding(.bottom, DetailPageMetrics.bottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func commitHeaderRename() {
        let trimmed = headerNameDraft.trimmingCharacters(in: .whitespaces)
        guard let p = playlist, !trimmed.isEmpty, trimmed != p.name else {
            isRenamingHeader = false
            return
        }
        playlistController.renamePlaylist(p.id, name: trimmed)
        isRenamingHeader = false
    }

    private func reload() {
        playlist = musicLibrary.playlist(playlistId)
        let allItems = musicLibrary.playlistItems(playlistId)
        let availableTracks = musicLibrary.tracksForPlaylist(playlistId)
        // tracksForPlaylist returns tracks for items whose track exists, in position order.
        // Build a {trackId: Track} map (allowing duplicates — same track id, last write
        // wins; data is identical) and then walk items aligning to surviving tracks.
        var trackById: [UUID: Track] = [:]
        for track in availableTracks { trackById[track.id] = track }
        var alignedItems: [PlaylistItem] = []
        var alignedTracks: [Track] = []
        for item in allItems {
            if let track = trackById[item.trackId] {
                alignedItems.append(item)
                alignedTracks.append(track)
            }
        }
        items = alignedItems
        tracks = alignedTracks
    }

    private func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        let queue = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard let queueIndex = queue.firstIndex(where: { $0.id == tracks[index].id }) else { return }
        player.requestPlay { player.playNow(tracks: queue, startingAt: queueIndex) }
    }

    private func playAll(shuffle: Bool) {
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available) }
        } else {
            player.requestPlay { player.playNow(tracks: available) }
        }
    }

    private func removeRows(_ rows: IndexSet) {
        let itemIds = rows.compactMap { items.indices.contains($0) ? items[$0].id : nil }
        for id in itemIds {
            playlistController.removeItem(id, from: playlistId)
        }
    }

    /// Move dragged rows to a new insertion index. Multi-row moves are split into
    /// individual moveItem calls; positions are computed via FractionalIndex.between
    /// using the gap created at the target.
    private func reorderRows(_ rows: IndexSet, to target: Int) {
        #if DEBUG
        print("[PL] reorderRows rows=\(Array(rows)) target=\(target) itemCount=\(items.count)")
        #endif
        // Build the post-move ordering of items so we can compute a fresh position for
        // each moved row. NSTableView's `target` is the row index AFTER the drop in the
        // current ordering, so we need to translate it.
        let movedIndices = rows.sorted()
        let stayingItems = items.enumerated().compactMap { idx, item in rows.contains(idx) ? nil : item }
        let movedItems = movedIndices.map { items[$0] }
        // Convert target (in original indexing) to an index into `stayingItems`.
        let stayingTargetIdx = movedIndices.reduce(target) { acc, removed in removed < acc ? acc - 1 : acc }
        let clampedTarget = min(max(stayingTargetIdx, 0), stayingItems.count)

        var prevPosition: String? = clampedTarget > 0 ? stayingItems[clampedTarget - 1].position : nil
        let endPosition: String? = clampedTarget < stayingItems.count ? stayingItems[clampedTarget].position : nil
        #if DEBUG
        print("[PL] stayingTargetIdx=\(stayingTargetIdx) clampedTarget=\(clampedTarget) prev=\(prevPosition ?? "nil") end=\(endPosition ?? "nil")")
        #endif
        for moved in movedItems {
            let newPosition = FractionalIndex.between(prevPosition, endPosition)
            #if DEBUG
            print("[PL] moveItem id=\(moved.id) oldPos=\(moved.position) newPos=\(newPosition)")
            #endif
            playlistController.moveItem(moved.id, to: newPosition, within: playlistId)
            prevPosition = newPosition
        }
    }
}

/// Playlists have no artwork of their own, so the header borrows their music: one cover
/// if that's all there is, otherwise a 2×2 of the first four distinct albums — the
/// convention Music.app and everything like it uses.
private struct PlaylistArtworkMosaic: View {
    let tracks: [Track]

    private var artworkURLs: [URL] {
        var seen = Set<UUID>()
        var urls: [URL] = []
        for track in tracks {
            guard let album = track.album, !seen.contains(album.id) else { continue }
            seen.insert(album.id)
            if let url = album.artworkUrl {
                urls.append(url)
                if urls.count == 4 { break }
            }
        }
        return urls
    }

    var body: some View {
        Group {
            let urls = artworkURLs
            if urls.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            } else if urls.count < 4 {
                ArtworkView(url: urls[0])
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ArtworkView(url: urls[0], cornerRadius: 0)
                        ArtworkView(url: urls[1], cornerRadius: 0)
                    }
                    HStack(spacing: 0) {
                        ArtworkView(url: urls[2], cornerRadius: 0)
                        ArtworkView(url: urls[3], cornerRadius: 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}
#endif
