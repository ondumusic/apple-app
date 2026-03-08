import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncService.self) private var syncService
    @Environment(PlaybackCache.self) private var playbackCache

    @State private var showClearCacheConfirmation = false

    private static let cacheLimitOptions: [(String, Int64)] = [
        ("500 MB", 500 * 1024 * 1024),
        ("1 GB", 1024 * 1024 * 1024),
        ("2 GB", 2 * 1024 * 1024 * 1024),
        ("5 GB", 5 * 1024 * 1024 * 1024),
        ("10 GB", 10 * 1024 * 1024 * 1024),
        ("Unlimited", 0),
    ]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Crossfade", isOn: crossfadeEnabled(settings: settings))

                if settings.crossfadeDuration > 0 {
                    HStack {
                        Slider(value: $settings.crossfadeDuration, in: 1...12, step: 1)
                        Text("\(Int(settings.crossfadeDuration))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Smoothly transition between tracks by overlapping the end of one with the start of the next.")
            }

            Section {
                Picker("Cache Limit", selection: $settings.playbackCacheLimit) {
                    ForEach(Self.cacheLimitOptions, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }

                HStack {
                    Text("Cache Size")
                    Spacer()
                    Text("\(playbackCache.formattedSize) (\(playbackCache.trackCount) tracks)")
                        .foregroundStyle(.secondary)
                }

                Button("Clear Cache", role: .destructive) {
                    showClearCacheConfirmation = true
                }
                .disabled(playbackCache.trackCount == 0)
                .confirmationDialog("Clear Playback Cache?", isPresented: $showClearCacheConfirmation) {
                    Button("Clear Cache", role: .destructive) {
                        playbackCache.clearCache()
                    }
                } message: {
                    Text("This will remove \(playbackCache.formattedSize) of cached audio. Tracks will be re-streamed on next play.")
                }
            } header: {
                Text("Playback Cache")
            } footer: {
                Text("Recently played tracks are cached locally to avoid re-streaming. Set a limit or choose Unlimited.")
            }

            Section {
                Picker("Concurrent Downloads", selection: $settings.maxConcurrentDownloads) {
                    ForEach([1, 2, 3, 4, 6, 8], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Number of tracks to download simultaneously. Higher values use more bandwidth.")
            }

            Section {
                HStack {
                    Text("Last Synced")
                    Spacer()
                    if syncService.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else if let date = syncService.lastSyncDate {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await syncService.sync() }
                } label: {
                    HStack {
                        Text("Sync Now")
                        if syncService.isSyncing {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(syncService.isSyncing)

                if let error = syncService.syncError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            } header: {
                Text("Library")
            }
        }
        .navigationTitle("Settings")
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        #endif
    }

    private func crossfadeEnabled(settings: SettingsStore) -> Binding<Bool> {
        Binding(
            get: { settings.crossfadeDuration > 0 },
            set: { settings.crossfadeDuration = $0 ? 1.0 : 0.0 }
        )
    }
}
