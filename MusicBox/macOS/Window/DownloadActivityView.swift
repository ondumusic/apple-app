#if os(macOS)
import SwiftUI

/// The Activity window's contents: every transfer, with its own controls.
///
/// Downloads used to carry this inline, which meant a page about what's on disk was
/// permanently half-occupied by things that are transient by nature. Mail, iTunes and
/// Safari all split it the same way — an ambient indicator you can ignore, and a window
/// when you actually care.
struct DownloadActivityView: View {
    @Environment(DownloadService.self) private var downloadService

    private var isEmpty: Bool {
        downloadService.activeDownloads.isEmpty
            && downloadService.pendingQueue.isEmpty
            && downloadService.failedDownloads.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isEmpty {
                header
                Divider()
            }
            if isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloads in progress appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        section("Downloading", rows: activeRows)
                        section("Queued", rows: queuedRows)
                        section("Failed", rows: failedRows)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 260)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // No title here — the window already carries one.
            Text(summary)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            if !downloadService.failedDownloads.isEmpty {
                Button("Retry All") {
                    for failed in downloadService.failedDownloads {
                        downloadService.retryDownload(failed)
                    }
                }
                .buttonStyle(.link)
                Button("Clear Failed") { downloadService.clearFailedDownloads() }
                    .buttonStyle(.link)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var summary: LocalizedStringKey {
        let remaining = downloadService.activeDownloads.count + downloadService.pendingQueue.count
        if remaining > 0 { return "^[\(remaining) remaining](inflect: true)" }
        if !downloadService.failedDownloads.isEmpty {
            return "^[\(downloadService.failedDownloads.count) failed](inflect: true)"
        }
        return "Idle"
    }

    @ViewBuilder
    private func section(_ title: String, rows: [ActivityRow]) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(rows) { row in
                ActivityRowView(row: row)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
    }

    private var activeRows: [ActivityRow] {
        downloadService.activeDownloadOrder.compactMap { trackId in
            guard let state = downloadService.activeDownloads[trackId] else { return nil }
            return ActivityRow(
                id: trackId, title: state.trackName, artist: state.artistName,
                progress: state.isPaused ? nil : downloadService.progressSnapshot[trackId],
                status: state.isPaused ? "Paused" : nil, isError: false,
                primary: state.isPaused
                    ? .init(label: "Resume", symbol: "play.circle") { downloadService.resumeDownload(trackId: trackId) }
                    : .init(label: "Pause", symbol: "pause.circle") { downloadService.pauseDownload(trackId: trackId) },
                secondary: .init(label: "Cancel", symbol: "xmark.circle") { downloadService.cancelDownload(trackId: trackId) }
            )
        }
    }

    private var queuedRows: [ActivityRow] {
        downloadService.pendingQueue.map { info in
            ActivityRow(id: info.track.id, title: info.track.name, artist: info.track.artist.name,
                        progress: nil, status: "Waiting", isError: false, primary: nil,
                        secondary: .init(label: "Cancel", symbol: "xmark.circle") {
                            downloadService.cancelDownload(trackId: info.track.id)
                        })
        }
    }

    private var failedRows: [ActivityRow] {
        downloadService.failedDownloads.map { failed in
            ActivityRow(id: failed.id, title: failed.trackName, artist: failed.artistName,
                        progress: nil, status: failed.reason, isError: true,
                        primary: .init(label: "Retry", symbol: "arrow.clockwise") {
                            downloadService.retryDownload(failed)
                        },
                        secondary: .init(label: "Dismiss", symbol: "xmark.circle") {
                            downloadService.dismissFailedDownload(failed)
                        })
        }
    }
}

struct ActivityRow: Identifiable {
    struct Action {
        let label: String
        let symbol: String
        let run: () -> Void
    }

    let id: UUID
    let title: String
    let artist: String
    let progress: Double?
    let status: String?
    let isError: Bool
    let primary: Action?
    let secondary: Action?
}

private struct ActivityRowView: View {
    let row: ActivityRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.artist)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let status = row.status {
                        Text("·").foregroundStyle(.secondary)
                        Text(status)
                            .foregroundStyle(row.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let progress = row.progress {
                // Determinate once bytes are flowing, indeterminate before — same width
                // either way so rows don't shift as downloads get going.
                Group {
                    if progress > 0 {
                        ProgressView(value: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                .frame(width: 90)
            }

            HStack(spacing: 4) {
                if let primary = row.primary { actionButton(primary) }
                if let secondary = row.secondary { actionButton(secondary) }
            }
        }
    }

    private func actionButton(_ action: ActivityRow.Action) -> some View {
        Button(action: action.run) {
            Image(systemName: action.symbol)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(action.label)
        .accessibilityLabel(action.label)
    }
}
#endif
