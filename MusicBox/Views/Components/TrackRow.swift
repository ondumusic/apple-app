import SwiftUI

struct TrackRow: View {
    @Environment(PlayerService.self) private var player
    @Environment(DownloadService.self) private var downloadService
    @Environment(OfflineStore.self) private var offlineStore
    @Environment(APIService.self) private var api

    let track: Track
    var album: Album? = nil
    var artist: Artist? = nil
    var showArtist = false
    var showNumber = true
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if showNumber {
                Text("\(track.number)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .lineLimit(1)

                if showArtist {
                    Text(track.artist.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(track.formattedDuration)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
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

            if offlineStore.isDownloaded(trackId: track.id) {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
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
                    Task {
                        let resolvedAlbum: Album
                        if let album {
                            resolvedAlbum = album
                        } else if let fetched = try? await api.fetchAlbum(track.albumId) {
                            resolvedAlbum = fetched
                        } else {
                            return
                        }
                        downloadService.download(track: track, album: resolvedAlbum, artist: artist ?? track.artist)
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
