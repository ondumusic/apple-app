import SwiftUI

/// What the server is complaining about, in the strip both platforms already use for
/// this sort of thing.
///
/// Dismissing is a server-side act: it clears the notice for every client, and the server
/// won't raise it again unless the problem is fixed and comes back. So there's no local
/// "seen" state here — unlike the version notice, which is this device's opinion.
struct ServerNoticesView: View {
    @Environment(SyncService.self) private var syncService

    var body: some View {
        ForEach(syncService.notices) { notice in
            HStack(spacing: 6) {
                Image(
                    systemName: notice.level == .warning
                        ? "exclamationmark.triangle.fill" : "info.circle.fill"
                )
                .foregroundStyle(notice.level == .warning ? .orange : .secondary)
                Text(notice.text)
                Spacer(minLength: 0)
                Button("Dismiss") {
                    Task { await syncService.dismiss(notice) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(Self.font)
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(for: notice.level))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    /// A warning gets the wash the paused-downloads and version notices use; an info is
    /// quieter, so the two stay distinguishable once there are more codes than one.
    private func background(for level: ServerNotice.Level) -> some ShapeStyle {
        level == .warning ? AnyShapeStyle(Color.orange.opacity(0.16)) : AnyShapeStyle(.quaternary)
    }

    #if os(macOS)
    private static let font: Font = .subheadline
    private static let horizontalPadding: CGFloat = 20
    private static let verticalPadding: CGFloat = 8
    #else
    private static let font: Font = .caption
    private static let horizontalPadding: CGFloat = 12
    private static let verticalPadding: CGFloat = 6
    #endif
}
