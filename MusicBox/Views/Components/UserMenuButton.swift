import SwiftUI

struct UserMenuButton: View {
    @Environment(DownloadService.self) private var downloadService
    let onDownloads: () -> Void
    var onSettings: (() -> Void)? = nil

    private var downloadCount: Int {
        downloadService.activeDownloads.count + downloadService.pendingQueue.count
    }

    var body: some View {
        Menu {
            Button(action: onDownloads) {
                if downloadCount > 0 {
                    Label("Downloads (\(downloadCount))", systemImage: "arrow.down.circle")
                } else {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            }
            if let onSettings {
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .overlay(alignment: .topTrailing) {
                    if downloadCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(.background, lineWidth: 1))
                            .offset(x: 2, y: -2)
                    }
                }
        }
    }
}
