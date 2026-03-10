import SwiftUI

struct TrackRow: View {
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(MusicLibrary.self) private var musicLibrary

    let track: Track
    var album: Album? = nil
    var artist: Artist? = nil
    var showArtist = false
    var showArtwork = false
    var showNumber = true
    var onTap: (() -> Void)? = nil

    private var isCurrentTrack: Bool {
        player.currentTrack?.id == track.id
    }

    private var artworkUrl: URL? {
        album?.artworkUrl ?? track.album?.artworkUrl
    }

    private var isAvailable: Bool {
        network.isOnline || musicLibrary.isDownloaded(trackId: track.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                ArtworkView(url: artworkUrl, cornerRadius: 4, thumbnailSize: 40)
                    .frame(width: 40, height: 40)
                    .opacity(isAvailable ? 1 : 0.4)
            }

            if showNumber {
                Group {
                    if isCurrentTrack {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    } else {
                        Text("\(track.number)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .foregroundStyle(isCurrentTrack ? AnyShapeStyle(.tint) : isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)

                if showArtist {
                    Text(track.artist.name)
                        .font(.caption)
                        .foregroundStyle(isAvailable ? .secondary : .tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.callout)
                .foregroundStyle(isAvailable ? .secondary : .tertiary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isAvailable else { return }
            onTap?()
        }
        .contextMenu {
            if isAvailable {
                Button {
                    player.playNext(tracks: [track], artworkURL: album?.artworkUrl)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    player.addToEnd(tracks: [track], artworkURL: album?.artworkUrl)
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }

                Divider()
            }

            TrackDownloadMenuItems(track: track, album: album, artist: artist)
        }
    }
}

/// Isolated subview so download/offline observation doesn't invalidate the parent TrackRow.
private struct TrackDownloadMenuItems: View {
    @Environment(DownloadService.self) private var downloadService
    @Environment(MusicLibrary.self) private var musicLibrary

    let track: Track
    let album: Album?
    let artist: Artist?

    var body: some View {
        if musicLibrary.isDownloaded(trackId: track.id) {
            Button(role: .destructive) {
                musicLibrary.markUndownloaded(trackId: track.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else if downloadService.isDownloading(trackId: track.id) {
            if let state = downloadService.activeDownloads[track.id], state.isPaused {
                Button {
                    downloadService.resumeDownload(trackId: track.id)
                } label: {
                    Label("Resume Download", systemImage: "play.circle")
                }
            } else {
                Button {
                    downloadService.pauseDownload(trackId: track.id)
                } label: {
                    Label("Pause Download", systemImage: "pause.circle")
                }
            }

            Button(role: .destructive) {
                downloadService.cancelDownload(trackId: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else if downloadService.isQueued(trackId: track.id) {
            Button(role: .destructive) {
                downloadService.cancelDownload(trackId: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else {
            Button {
                let resolvedAlbum = album ?? musicLibrary.album(track.albumId)
                guard let resolvedAlbum else { return }
                let albumArtist = artist ?? musicLibrary.artist(resolvedAlbum.artistId) ?? track.artist
                downloadService.download(track: track, album: resolvedAlbum, artist: albumArtist)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}
