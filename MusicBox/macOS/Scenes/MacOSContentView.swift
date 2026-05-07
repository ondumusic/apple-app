#if os(macOS)
import SwiftUI

/// Root macOS content view. SwiftUI shell that hosts the AppKit-backed sidebar,
/// track tables, toolbar, and mini-player. Layout fills in piece by piece — see
/// project_macos_rebuild_plan.md for the per-surface plan.
struct MacOSContentView: View {
    @State private var showQueue = false

    var body: some View {
        ContentUnavailableView {
            Label("macOS rebuild in progress", systemImage: "hammer")
        } description: {
            Text("Sidebar, track tables, and mini-player land here next.")
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { PlayerToolbar(showQueue: $showQueue) }
        .sheet(isPresented: $showQueue) {
            QueueSheetPlaceholder(isPresented: $showQueue)
        }
    }
}

private struct QueueSheetPlaceholder: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Queue")
                .font(.headline)
            Text("QueueView will be re-wired to NSTableView in the tracks step.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 320, height: 200)
    }
}
#endif
