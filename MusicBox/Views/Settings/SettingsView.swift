import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncService.self) private var syncService
    @Environment(AuthService.self) private var auth
    @Environment(PlaybackCache.self) private var playbackCache

    @State private var showClearCacheConfirmation = false
    @State private var showLogoutConfirmation = false

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
                Toggle("Artwork-Tinted Player", isOn: $settings.artworkTintedPlayer)
                Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Colors the player background based on the current track's album artwork.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Color")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(AccentColor.allCases, id: \.self) { accentOption in
                            if accentOption == .custom {
                                ColorPicker("", selection: customColorBinding(settings: settings), supportsOpacity: false)
                                    .labelsHidden()
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if settings.accentColor == .custom {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            } else {
                                Circle()
                                    .fill(accentOption.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if settings.accentColor == accentOption {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .onTapGesture {
                                        settings.accentColor = accentOption
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
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

            if SettingsStore.enableDownloadQuality {
                Section {
                    Picker("Streaming Quality", selection: $settings.streamingQuality) {
                        ForEach(StreamingQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }

                    Picker("Download Quality", selection: $settings.downloadQuality) {
                        ForEach(DownloadQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                } header: {
                    Text("Quality")
                } footer: {
                    Text("Streaming quality applies when playing from the server. Download quality only affects new downloads. Original streams the file as-is.")
                }
            }

            Section {
                Picker("Concurrent Downloads", selection: $settings.maxConcurrentDownloads) {
                    ForEach([1, 2, 3, 4, 6, 8], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                
                Toggle("Auto-Download New Tracks", isOn: $settings.autoDownloadNewTracks)
            } header: {
                Text("Downloads")
            } footer: {
                Text("Automatically download new tracks added to the server after each sync.")
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

            Section {
                if let user = auth.currentUser {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(user.username)
                            .foregroundStyle(.secondary)
                    }
                }

                if let host = auth.apiService?.baseURL.host() {
                    HStack {
                        Text("Server")
                        Spacer()
                        Text(host)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Sign Out", role: .destructive) {
                    showLogoutConfirmation = true
                }
                .confirmationDialog("Sign Out?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        playbackCache.clearCache()
                        auth.logout()
                    }
                } message: {
                    Text("This will remove all offline data including downloads, cached artwork, and your synced library from this device.")
                }
            } header: {
                Text("Account")
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

    private func customColorBinding(settings: SettingsStore) -> Binding<Color> {
        Binding(
            get: { settings.customAccentColor },
            set: { newColor in
                settings.accentColor = .custom
                if let components = newColor.rgbComponents {
                    settings.customAccentRed = components.red
                    settings.customAccentGreen = components.green
                    settings.customAccentBlue = components.blue
                }
            }
        )
    }
}

private extension Color {
    var rgbComponents: (red: Double, green: Double, blue: Double)? {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil) else { return nil }
        return (Double(r), Double(g), Double(b))
        #else
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        #endif
    }
}
