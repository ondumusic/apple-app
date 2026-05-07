#if os(macOS)
import SwiftUI

/// Root macOS content view. SwiftUI shell that hosts the AppKit-backed sidebar,
/// track tables, toolbar, and mini-player. Layout will be filled in piece by piece
/// (see project_macos_rebuild_plan.md for the per-surface plan).
struct MacOSContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label("macOS rebuild in progress", systemImage: "hammer")
        } description: {
            Text("AppKit shell scaffolding lands here next.")
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
#endif
