import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    /// Optional because Settings outlives being signed in: Sign Out is in this window,
    /// and Cmd+, opens it again afterwards. There's no sync service either side of that,
    /// and a non-optional read of an absent environment object traps.
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(AuthService.self) private var auth
    @Environment(PlaybackCache.self) private var playbackCache

    #if DEBUG && os(iOS)
    /// Only to check that the gain reaches the player on a device, where the logs aren't
    /// in reach. The macOS Settings scene has no player in its environment.
    @Environment(PlayerService.self) private var debugPlayer
    #endif

    @State private var showClearCacheConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var showRebuildConfirmation = false

    fileprivate static let cacheLimitOptions: [(String, Int64)] = [
        ("500 MB", 500 * 1024 * 1024),
        ("1 GB", 1024 * 1024 * 1024),
        ("2 GB", 2 * 1024 * 1024 * 1024),
        ("5 GB", 5 * 1024 * 1024 * 1024),
        ("10 GB", 10 * 1024 * 1024 * 1024),
        ("Unlimited", 0),
    ]

    var body: some View {
        #if os(macOS)
        macTabbedBody
        #else
        Form {
            playbackSection
            normalizeVolumeSection
            recordPlaysSection
            appearanceSection
            accentColorSection
            cacheSection
            qualitySection
            downloadsSection
            librarySection
            accountSection
            aboutSection
        }
        .navigationTitle("Settings")
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macTabbedBody: some View {
        TabView {
            Form {
                playbackSection
                normalizeVolumeSection
                recordPlaysSection
                qualitySection
            }
            .formStyle(.grouped)
            .tabItem { Label("Playback", systemImage: "play.circle") }

            Form {
                appearanceSection
                accentColorSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Appearance", systemImage: "paintbrush") }

            Form {
                cacheSection
                downloadsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Storage", systemImage: "internaldrive") }

            Form {
                librarySection
                accountSection
                aboutSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 600, height: 480)
    }
    #endif

    @ViewBuilder
    private var playbackSection: some View {
        @Bindable var settings = settings
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
    }

    @ViewBuilder
    private var normalizeVolumeSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Normalize Volume", isOn: $settings.normalizeVolume)
            #if DEBUG && os(iOS)
            LabeledContent("Applied gain") {
                Text(debugAppliedGain).monospacedDigit().foregroundStyle(.secondary)
            }
            #endif
        } footer: {
            Text(
                "Plays every track at a similar loudness, so quiet albums and loud ones don't jump. Albums keep their own quiet and loud moments. Turns the volume down, never up."
            )
        }
    }

    @ViewBuilder
    private var recordPlaysSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Record Plays", isOn: $settings.recordPlays)
        } footer: {
            Text(
                "Counts a track as played once you've heard most of it, and tells your server. Turning this off stops this device counting; plays already recorded are kept, and your other devices carry on."
            )
        }
    }

    #if DEBUG && os(iOS)
    private var debugAppliedGain: String {
        guard debugPlayer.currentTrack != nil else { return "nothing playing" }
        let dB = 20 * log10(Double(debugPlayer.primaryGain))
        return String(format: "%.1f dB", dB)
    }
    #endif

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Artwork-Tinted Player", isOn: $settings.artworkTintedPlayer)
            #if os(iOS)
            Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
            #endif
        } header: {
            Text("Appearance")
        } footer: {
            #if os(macOS)
            Text("Colors the mini player background based on the current track's album artwork.")
            #else
            Text("Colors the player background based on the current track's album artwork.")
            #endif
        }
    }

    @ViewBuilder
    private var accentColorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Accent Color")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(AccentColor.allCases, id: \.self) { accentOption in
                        if accentOption == .custom {
                            customColorSwatch
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
                                .onTapGesture { settings.accentColor = accentOption }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var cacheSection: some View {
        @Bindable var settings = settings
        Section {
            Picker("Cache Limit", selection: $settings.playbackCacheLimit) {
                ForEach(Self.cacheLimitOptions, id: \.1) { label, value in
                    Text(label).tag(value)
                }
            }
            HStack {
                Text("Cache Size")
                Spacer()
                Text("\(playbackCache.formattedSize) (^[\(playbackCache.trackCount) track](inflect: true))")
                    .foregroundStyle(.secondary)
            }
            Button("Clear Cache", role: .destructive) { showClearCacheConfirmation = true }
                .disabled(playbackCache.trackCount == 0)
                .confirmationDialog("Clear Playback Cache?", isPresented: $showClearCacheConfirmation) {
                    Button("Clear Cache", role: .destructive) { playbackCache.clearCache() }
                } message: {
                    Text(
                        "This will remove \(playbackCache.formattedSize) of cached audio. Tracks will be re-streamed on next play."
                    )
                }
        } header: {
            Text("Playback Cache")
        } footer: {
            Text("Recently played tracks are cached locally to avoid re-streaming. Set a limit or choose Unlimited.")
        }
    }

    @ViewBuilder
    private var qualitySection: some View {
        @Bindable var settings = settings
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
                Text(
                    "Streaming quality applies when playing from the server. Download quality only affects new downloads."
                )
            }
        }
    }

    @ViewBuilder
    private var downloadsSection: some View {
        @Bindable var settings = settings
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
    }

    @ViewBuilder
    private var librarySection: some View {
        if let syncService {
            Section {
                HStack {
                    Text("Last Synced")
                    Spacer()
                    if syncService.isSyncing {
                        ProgressView().controlSize(.small)
                    } else if let date = syncService.lastSyncDate {
                        Text(date, style: .relative).foregroundStyle(.secondary)
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await syncService.sync() }
                } label: {
                    HStack {
                        Text("Sync Now")
                        if syncService.isSyncing {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(syncService.isSyncing)
                Button("Rebuild Library") { showRebuildConfirmation = true }
                    .disabled(syncService.isSyncing)
                    .confirmationDialog("Rebuild Library?", isPresented: $showRebuildConfirmation) {
                        Button("Rebuild") { Task { await syncService.rebuildLibrary() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Downloads your whole library again from the server. Downloaded music and playlists are kept."
                        )
                    }
                if let error = syncService.syncError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            } header: {
                Text("Library")
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            Link("Website", destination: SiteLinks.website)
            Link("Privacy Policy", destination: SiteLinks.privacyPolicy)
        } header: {
            Text("About")
        }
    }

    /// Version and build, the way TestFlight lists a build, so a report can name it.
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    private var accountSection: some View {
        Section {
            if let user = auth.currentUser {
                HStack {
                    Text("Signed in as")
                    Spacer()
                    Text(user.username).foregroundStyle(.secondary)
                }
            }
            if let host = auth.apiService?.baseURL.host() {
                HStack {
                    Text("Server")
                    Spacer()
                    Text(host).foregroundStyle(.secondary)
                }
            }
            if let serverVersion = syncService?.serverVersion {
                HStack {
                    Text("Server Version")
                    Spacer()
                    Text(serverVersion).foregroundStyle(.secondary)
                }
            }
            if auth.isLoggedIn {
                Button("Sign Out", role: .destructive) { showLogoutConfirmation = true }
                    .confirmationDialog("Sign Out?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) {
                            playbackCache.clearCache()
                            auth.logout()
                        }
                    } message: {
                        Text(
                            "This will remove all offline data including downloads, cached artwork, and your synced library from this device."
                        )
                    }
            } else {
                Text("Not signed in").foregroundStyle(.secondary)
            }
        } header: {
            Text("Account")
        }
    }

    private func crossfadeEnabled(settings: SettingsStore) -> Binding<Bool> {
        Binding(
            get: { settings.crossfadeDuration > 0 },
            set: { settings.crossfadeDuration = $0 ? 1.0 : 0.0 }
        )
    }

    /// macOS draws ColorPicker as its colour well — a capsule on macOS 26 and later,
    /// which sat oddly in a row of circles. A circle in the style of iOS's picker
    /// instead, opening the standard colour panel.
    @ViewBuilder
    private var customColorSwatch: some View {
        #if os(macOS)
        let binding = customColorBinding(settings: settings)
        Circle()
            .fill(
                AngularGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                    center: .center)
            )
            .overlay {
                Circle()
                    .fill(settings.customAccentColor)
                    .padding(4)
            }
            .contentShape(Circle())
            .onTapGesture {
                CustomAccentColorPanel.shared.show(initial: NSColor(binding.wrappedValue)) {
                    binding.wrappedValue = Color(nsColor: $0)
                }
            }
            .help("Choose a custom color")
        #else
        ColorPicker("", selection: customColorBinding(settings: settings), supportsOpacity: false)
            .labelsHidden()
        #endif
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

extension Color {
    fileprivate var rgbComponents: (red: Double, green: Double, blue: Double)? {
        #if os(iOS)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: nil) else { return nil }
        return (Double(r), Double(g), Double(b))
        #else
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        #endif
    }
}

#if os(macOS)
/// The shared colour panel reports changes by target-action, which a SwiftUI view can't
/// be the target of.
private final class CustomAccentColorPanel: NSObject {
    static let shared = CustomAccentColorPanel()
    private var onChange: ((NSColor) -> Void)?

    func show(initial: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
#endif
