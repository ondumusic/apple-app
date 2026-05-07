#if os(macOS)
import SwiftUI

/// Root macOS content view. SwiftUI shell that hosts the AppKit-backed sidebar,
/// track tables, toolbar, and mini-player. Layout fills in piece by piece — see
/// project_macos_rebuild_plan.md for the per-surface plan.
struct MacOSContentView: View {
    @Environment(MusicLibrary.self) private var musicLibrary

    @State private var showQueue = false
    @State private var sidebarSelection: SidebarSelection? = .category(.artists)

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $sidebarSelection, musicLibrary: musicLibrary)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            DetailPlaceholder(selection: sidebarSelection)
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { PlayerToolbar(showQueue: $showQueue) }
        .sheet(isPresented: $showQueue) {
            QueueSheetPlaceholder(isPresented: $showQueue)
        }
    }
}

private struct DetailPlaceholder: View {
    let selection: SidebarSelection?

    var body: some View {
        switch selection {
        case .category(.songs):
            SongsViewMac()
        case .category(let cat):
            ContentUnavailableView {
                Label(cat.title, systemImage: cat.iconName)
            } description: {
                Text("Detail view for \(cat.title) lands in the tracks/detail step.")
            }
        case .playlist(let id):
            ContentUnavailableView {
                Label("Playlist", systemImage: "music.note.list")
            } description: {
                Text("Playlist \(id.uuidString.prefix(8))…")
            }
        case .none:
            ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
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
