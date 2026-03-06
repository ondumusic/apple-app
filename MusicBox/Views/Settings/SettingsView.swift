import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncService.self) private var syncService

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
                    Task { try? await syncService.sync() }
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
