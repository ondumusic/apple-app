import SwiftUI

extension Notification.Name {
    static let scrollToTop = Notification.Name("MusicBox.scrollToTop")
    static let navigateToArtist = Notification.Name("MusicBox.navigateToArtist")
    static let navigateToAlbum = Notification.Name("MusicBox.navigateToAlbum")
}

struct ContentView: View {
    @Environment(SyncService.self) private var syncService

    var body: some View {
        if syncService.hasCompletedInitialSync {
            #if os(iOS)
            iOSRootView()
            #else
            macOSRootView()
            #endif
        } else {
            SyncProgressView()
                .task {
                    try? await syncService.sync()
                }
        }
    }
}

private struct SyncProgressView: View {
    @Environment(SyncService.self) private var syncService

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Syncing Library...")
                .font(.headline)
            if let progress = syncService.syncProgress {
                Group {
                    if progress.trackCount > 0 {
                        Text("\(progress.artistCount) artists, \(progress.albumCount) albums, \(progress.trackCount) tracks")
                    } else if progress.albumCount > 0 {
                        Text("\(progress.artistCount) artists, \(progress.albumCount) albums")
                    } else if progress.artistCount > 0 {
                        Text("\(progress.artistCount) artists")
                    }
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .monospacedDigit()
            }
        }
    }
}
