import SwiftUI

extension Notification.Name {
    static let scrollToTop = Notification.Name("MusicBox.scrollToTop")
    static let navigateToArtist = Notification.Name("MusicBox.navigateToArtist")
    static let navigateToAlbum = Notification.Name("MusicBox.navigateToAlbum")
    static let sessionExpired = Notification.Name("MusicBox.sessionExpired")
}

struct ContentView: View {
    @Environment(SyncService.self) private var syncService
    @Environment(PlaylistController.self) private var playlistController

    var body: some View {
        Group {
            if syncService.hasCompletedInitialSync {
                #if os(iOS)
                iOSRootView()
                    .task { await syncService.syncIfNeeded() }
                #else
                macOSRootView()
                    .task { await syncService.syncIfNeeded() }
                #endif
            } else {
                SyncProgressView()
                    .task {
                        try? await syncService.sync()
                    }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { playlistController.lastError != nil },
                set: { if !$0 { playlistController.lastError = nil } }
            ),
            presenting: playlistController.lastError
        ) { _ in
            Button("OK", role: .cancel) { playlistController.lastError = nil }
        } message: { message in
            Text(message)
        }
    }
}

private struct SyncProgressView: View {
    @Environment(SyncService.self) private var syncService

    var body: some View {
        VStack(spacing: 16) {
            if let error = syncService.syncError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Sync Failed")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button("Retry") {
                    Task { await syncService.sync() }
                }
                .buttonStyle(.bordered)
            } else {
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
}
