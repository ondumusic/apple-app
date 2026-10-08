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
    @Environment(NetworkMonitor.self) private var network
    @State private var showCancelAllConfirmation = false

    /// Anything still going or waiting — failed rows alone don't warrant bulk transport.
    private var hasTransfers: Bool {
        !downloadService.activeDownloads.isEmpty || !downloadService.pendingQueue.isEmpty
    }

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
            DownloadPausedNotice()
            if isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloads in progress appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Lazy: a full-library queue is thousands of rows, and a plain
                    // VStack builds every one of them when the window opens. The row
                    // identity bug that prompted the switch away from LazyVStack was the
                    // shared ids, which are section-scoped now.
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
        .pageBackground()
        .confirmationDialog("Cancel All Downloads?", isPresented: $showCancelAllConfirmation,
                            titleVisibility: .visible) {
            Button("Cancel All", role: .destructive) { downloadService.cancelAll() }
            Button("Keep Downloading", role: .cancel) {}
        } message: {
            Text("Nothing already downloaded is removed — only what's still in progress or waiting.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // No title here — the window already carries one.
            Text(summary)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            if hasTransfers {
                Button(downloadService.isPaused ? "Resume All" : "Pause All") {
                    if downloadService.isPaused {
                        downloadService.resumeAll()
                    } else {
                        downloadService.pauseAll()
                    }
                }
                .buttonStyle(.link)
                Button("Cancel All") { showCancelAllConfirmation = true }
                    .buttonStyle(.link)
            }
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
        // The noun goes inside the markup — wrapping "remaining" made the inflection
        // engine pluralise that instead, which came out as "remained".
        let remaining = downloadService.activeDownloads.count + downloadService.pendingQueue.count
        if remaining > 0 { return "^[\(remaining) download](inflect: true) remaining" }
        if !downloadService.failedDownloads.isEmpty {
            return "^[\(downloadService.failedDownloads.count) download](inflect: true) failed"
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
                id: "active-\(trackId)", title: state.trackName, artist: state.artistName,
                // Zero rather than nil before bytes flow, so the column is always
                // present and shows an indeterminate bar instead of a gap.
                progress: state.isPaused ? nil : (downloadService.progressSnapshot[trackId] ?? 0),
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
            ActivityRow(id: "queued-\(info.track.id)", title: info.track.name, artist: info.track.artist.name,
                        progress: nil, status: "Waiting", isError: false, primary: nil,
                        secondary: .init(label: "Cancel", symbol: "xmark.circle") {
                            downloadService.cancelDownload(trackId: info.track.id)
                        })
        }
    }

    private var failedRows: [ActivityRow] {
        downloadService.failedDownloads.map { failed in
            ActivityRow(id: "failed-\(failed.id)", title: failed.trackName, artist: failed.artistName,
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

    let id: String
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
