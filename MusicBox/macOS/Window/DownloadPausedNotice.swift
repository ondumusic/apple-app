#if os(macOS)
import SwiftUI

/// Why nothing is downloading despite a queue. Four conditions stop transfers dead —
/// Low Power Mode, low disk, Low Data Mode, and a manual pause — and macOS surfaced none
/// of them: the shared iOS view has this notice, and the Mac Downloads rebuild dropped it.
/// A queue that silently never starts, with nothing in the console, is the result.
struct DownloadPausedNotice: View {
    @Environment(DownloadService.self) private var downloadService
    @Environment(NetworkMonitor.self) private var network

    /// Only the Low Power Mode pause is a preference the user can reasonably overrule.
    private var isOverridable: Bool {
        downloadService.downloadsPausedReason == .lowPowerMode
    }

    private var reason: LocalizedStringKey? {
        let hasWork = !downloadService.activeDownloads.isEmpty || !downloadService.pendingQueue.isEmpty
        guard hasWork else { return nil }
        if downloadService.isPaused { return "Downloads paused" }
        if let reason = downloadService.downloadsPausedReason {
            switch reason {
            case .lowPowerMode: return "Downloads paused — Low Power Mode is on"
            case .lowDiskSpace: return "Downloads paused — this Mac is low on storage"
            }
        }
        if network.isConstrained { return "Downloads paused — Low Data Mode is on" }
        return nil
    }

    var body: some View {
        if let reason {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(reason)
                Spacer(minLength: 0)
                if isOverridable {
                    Button("Download Anyway") { downloadService.ignoresLowPowerMode = true }
                        .buttonStyle(.link)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.16))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
#endif
