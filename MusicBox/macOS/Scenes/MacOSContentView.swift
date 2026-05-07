#if os(macOS)
import SwiftUI

/// Root macOS content view. SwiftUI shell that hosts the AppKit-backed sidebar,
/// track tables, toolbar, and mini-player. Layout fills in piece by piece — see
/// project_macos_rebuild_plan.md for the per-surface plan.
struct MacOSContentView: View {
    @Environment(MusicLibrary.self) private var musicLibrary

    @State private var showQueue = false
    @State private var sidebarSelection: SidebarSelection? = .category(.artists)
    @State private var detailPath = NavigationPath()

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $sidebarSelection, musicLibrary: musicLibrary)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            NavigationStack(path: $detailPath) {
                DetailPlaceholder(selection: sidebarSelection)
                    .navigationDestination(for: Album.self) { album in
                        AlbumDetailMac(album: album)
                    }
                    .navigationDestination(for: Artist.self) { artist in
                        ArtistDetailMac(artist: artist)
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { PlayerToolbar(showQueue: $showQueue) }
        .sheet(isPresented: $showQueue) {
            QueueSheetPlaceholder(isPresented: $showQueue)
        }
        .onChange(of: sidebarSelection) {
            // Switching sidebar items resets the drill-in stack so we don't show stale
            // album/artist detail under a new section.
            detailPath = NavigationPath()
        }
    }
}

private struct DetailPlaceholder: View {
    let selection: SidebarSelection?

    var body: some View {
        switch selection {
        case .category(.songs):
            SongsViewMac()
        case .category(.albums):
            AlbumsViewMac()
        case .category(.artists):
            ArtistsViewMac()
        case .category(.downloads):
            DownloadsView()
        case .playlist(let id):
            PlaylistDetailMac(playlistId: id)
                .id(id)
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
