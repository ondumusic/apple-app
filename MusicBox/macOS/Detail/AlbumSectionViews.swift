#if os(macOS)
import SwiftUI

/// Right-side metadata for an album section: title, year, play/shuffle/download
/// buttons. The album artwork is drawn separately as a left-edge overlay
/// (`AlbumArtworkOverlay`) over multiple track rows — iTunes-style split layout.
/// Used both in ArtistDetailMac (one per album section) and as the entire header
/// of AlbumDetailMac (single section, single album).
struct AlbumSectionHeader: View {
    let album: Album
    let onPlay: () -> Void
    let onShuffle: () -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    /// Distance from the table's left edge to the album title. In the split layout this
    /// clears the artwork gutter; compact just insets from the edge.
    var leadingInset: CGFloat = 240
    /// Compact mode: no artwork gutter exists, so the header carries the cover and the
    /// summary line that would otherwise sit under the overlay.
    var inlineArtwork: Bool = false
    /// Set when this album is a pushed destination — the chevron sits with the title
    /// rather than in a bar of its own, matching the search show-all pages.
    var onBack: (() -> Void)?

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(DownloadService.self) private var downloadService

    private enum DownloadState { case downloading, partial, complete }
    private var downloadState: DownloadState {
        if downloadService.isAlbumDownloading(albumId: album.id) { return .downloading }
        if musicLibrary.isAlbumFullyDownloaded(albumId: album.id) { return .complete }
        return .partial
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if inlineArtwork {
                NavigationLink(value: album) {
                    ArtworkView(url: album.artworkUrl)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
            }
            if onBack != nil {
                BackToResultsButton()
                    .padding(.trailing, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                Group {
                    if inlineArtwork {
                        if let year = album.releaseYear {
                            Text("\(String(year)) · ") + albumSummary(album)
                        } else {
                            albumSummary(album)
                        }
                    } else if let year = album.releaseYear {
                        Text(String(year))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { onPlay() } label: {
                    Image(systemName: "play.fill")
                }
                Button { onShuffle() } label: {
                    Image(systemName: "shuffle")
                }
                switch downloadState {
                case .downloading:
                    Button { onCancelDownload() } label: {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                case .partial:
                    Button { onDownload() } label: {
                        Image(systemName: "arrow.down")
                    }
                case .complete:
                    EmptyView()
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
        // In the split layout this pushes past the spacer column (artworkSize 160 + 2 ×
        // inset 20 = 200) AND past the number column (36) plus the title cell's leading
        // text inset (4), so the album title sits in the same x position as the track
        // titles below.
        .padding(.leading, leadingInset)
        .padding(.trailing, 20)
        // Top padding matches artworkInset (20) so the title baseline aligns with the
        // top edge of the artwork.
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

/// "12 songs, 44 min" — under the overlay artwork in the split layout, on the header's
/// secondary line when compact.
private func albumSummary(_ album: Album) -> Text {
    let trackCount = album.tracks?.count ?? 0
    let total = album.tracks?.reduce(0) { $0 + $1.duration } ?? 0
    return Text("^[\(trackCount) song](inflect: true), \(formattedTotalDuration(total))")
}

/// "44 min" / "1 hr 12 min" — collection totals, as opposed to Track.formattedDuration's
/// m:ss for a single song.
func formattedTotalDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int((seconds / 60).rounded())
    guard totalMinutes >= 60 else { return "\(max(1, totalMinutes)) min" }
    let hours = totalMinutes / 60
    let mins = totalMinutes % 60
    return mins == 0 ? "\(hours) hr" : "\(hours) hr \(mins) min"
}

/// Album artwork rendered in the leftmost spacer-column area of TracksTable. Sized
/// to match `artworkSize` × `artworkSize`; positioned by the table to anchor at the
/// section's header row and extend down across the first few track rows.
struct AlbumArtworkOverlay: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: album) {
                ArtworkView(url: album.artworkUrl)
                    .frame(width: 160, height: 160)
            }
            .buttonStyle(.plain)
            albumSummary(album)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
        }
    }
}
#endif
