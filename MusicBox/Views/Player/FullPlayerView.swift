import SwiftUI
import AVKit
import MediaPlayer

struct FullPlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var artworkColor: Color?
    @State private var audioRouteName: String?

    private var artworkURL: URL? {
        player.queue.indices.contains(player.effectiveIndex)
            ? player.queue[player.effectiveIndex].artworkURL : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Artwork — centered in available space
                ArtworkView(url: artworkURL, cornerRadius: 12)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(radius: player.isPlaying ? 16 : 6, y: player.isPlaying ? 8 : 4)
                    .scaleEffect(player.isPlaying ? 1.0 : 0.85)
                    .animation(.spring(duration: 0.5, bounce: 0.3), value: player.isPlaying)
                    .id(player.currentTrack?.id)
                    .transition(.blurReplace)
                    .animation(.easeInOut(duration: 0.4), value: player.currentTrack?.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Controls pinned to bottom
                VStack(spacing: 20) {
                    // Track info
                    trackInfo
                        .padding(.horizontal)

                    // Scrubber
                    PlayerScrubber()
                        .padding(.horizontal)

                    // Transport controls
                    TransportControls()
                        .padding(.horizontal)

                    // Volume
                    PlayerVolumeSlider()
                        .padding(.horizontal)

                    // Bottom row: AirPlay left, queue right
                    HStack {
                        #if os(iOS)
                        HStack(spacing: 4) {
                            AirPlayButton(
                                activeTintColor: UIColor(settings.resolvedAccentColor),
                                routeActive: audioRouteName != nil
                            )
                            .frame(width: 48, height: 48)
                            if let audioRouteName {
                                Text(audioRouteName)
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundStyle(settings.resolvedAccentColor)
                                    .lineLimit(1)
                                    .overlay {
                                        AirPlayTapArea()
                                            .frame(width: 200, height: 48)
                                    }
                            }
                        }
                        #else
                        Spacer().frame(width: 48)
                        #endif

                        Spacer()

                        Button { showQueue = true } label: {
                            Image(systemName: "list.bullet")
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .overlay(alignment: .topTrailing) {
                                    queueBadge
                                }
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }
            .background {
                ZStack {
                    if settings.artworkTintedPlayer, let artworkColor {
                        LinearGradient(
                            stops: [
                                .init(color: artworkColor, location: 0),
                                .init(color: artworkColor.opacity(0.6), location: 0.6),
                                .init(color: artworkColor.opacity(0.3), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color(.systemBackground)
                    }
                }
                .ignoresSafeArea()
            }
            .foregroundStyle(settings.artworkTintedPlayer && artworkColor != nil ? .white : .primary)
            .tint(settings.artworkTintedPlayer && artworkColor != nil ? .white : .accentColor)
            .task(id: settings.artworkTintedPlayer) {
                guard settings.artworkTintedPlayer else {
                    withAnimation(.easeInOut(duration: 0.5)) { artworkColor = nil }
                    return
                }
                await updateArtworkColor()
            }
            .onChange(of: player.currentTrack?.id) {
                guard settings.artworkTintedPlayer else { return }
                Task { await updateArtworkColor() }
            }
            .onAppear { updateAudioRoute() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                updateAudioRoute()
            }
            .sheet(isPresented: $showQueue) {
                NavigationStack {
                    QueueView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showQueue = false }
                            }
                        }
                }
            }
            .preferredColorScheme(settings.artworkTintedPlayer && artworkColor != nil ? .dark : nil)
        }
    }

    private func updateArtworkColor() async {
        let color = await ArtworkColorExtractor.extractColor(from: artworkURL)
        withAnimation(.easeInOut(duration: 0.5)) { artworkColor = color }
    }

    private func updateAudioRoute() {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let externalOutput = outputs.first { output in
            output.portType != .builtInSpeaker && output.portType != .builtInReceiver
        }
        guard let externalOutput else {
            audioRouteName = nil
            return
        }
        audioRouteName = externalOutput.portName
        #endif
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text(player.currentTrack?.name ?? "")
                .font(.title2.bold())
                .lineLimit(1)

            if let track = player.currentTrack {
                Menu {
                    Button {
                        let artist = track.artist
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .navigateToArtist, object: artist)
                        }
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }

                    if let trackAlbum = track.album {
                        Button {
                            let album = Album(
                                id: trackAlbum.id,
                                artistId: track.artistId,
                                name: trackAlbum.name,
                                sortName: trackAlbum.name,
                                slug: "",
                                artworkUrl: trackAlbum.artworkUrl
                            )
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .navigateToAlbum, object: album)
                            }
                        } label: {
                            Label("Go to Album", systemImage: "square.stack")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(track.artist.name)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Queue Badge

    @ViewBuilder
    private var queueBadge: some View {
        if player.isShuffled && player.repeatMode != .off {
            // Both active — show shuffle icon (repeat is implied)
            badgeIcon("shuffle")
        } else if player.isShuffled {
            badgeIcon("shuffle")
        } else if player.repeatMode == .one {
            badgeIcon("repeat.1")
        } else if player.repeatMode == .all {
            badgeIcon("repeat")
        }
    }

    private func badgeIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(3)
            .background(settings.resolvedAccentColor, in: Circle())
            .offset(x: 6, y: -6)
    }

}

// MARK: - Scrubber (isolated from main body to avoid progress-driven rebuilds)

private struct PlayerScrubber: View {
    @Environment(PlayerService.self) private var player
    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        let currentValue = isDragging ? dragValue : player.progress

        VStack(spacing: 4) {
            CustomSlider(
                value: Binding(
                    get: { isDragging ? dragValue : player.progress },
                    set: { newValue in
                        dragValue = newValue
                        if !isDragging { isDragging = true }
                    }
                ),
                range: 0...max(player.duration, 1),
                isDragging: $isDragging,
                trackHeight: 6,
                activeTrackHeight: 10,
                onEnded: {
                    player.seek(to: dragValue)
                    isDragging = false
                }
            )
            .frame(height: 32)

            HStack {
                Text(formatTime(currentValue))
                    .font(.caption)
                    .foregroundStyle(isDragging ? .primary : .secondary)
                    .monospacedDigit()
                Spacer()
                Text("-" + formatTime(max(0, player.duration - currentValue)))
                    .font(.caption)
                    .foregroundStyle(isDragging ? .primary : .secondary)
                    .monospacedDigit()
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Transport Controls (isolated to avoid progress-driven rebuilds)

private struct TransportControls: View {
    @Environment(PlayerService.self) private var player

    var body: some View {
        HStack(spacing: 40) {
            Button { Haptics.light(); player.back() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!player.canGoBack)

            Button { Haptics.medium(); player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
            }
            .buttonStyle(.plain)

            Button { Haptics.light(); player.skip() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!player.canSkip)
        }
    }
}

// MARK: - Volume Slider (isolated)

private struct PlayerVolumeSlider: View {
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(isDragging ? .primary : .secondary)
                .frame(width: 16, alignment: .center)

            VolumeSlider(isDragging: $isDragging)
                .frame(height: 32)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption2)
                .foregroundStyle(isDragging ? .primary : .secondary)
                .frame(width: 16, alignment: .center)
        }
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - Custom Slider (no thumb)

private struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Binding var isDragging: Bool
    var trackHeight: CGFloat = 4
    var activeTrackHeight: CGFloat = 8
    var fillColor: Color = .primary
    let onEnded: () -> Void

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    var body: some View {
        GeometryReader { geo in
            let height: CGFloat = isDragging ? activeTrackHeight : trackHeight
            let width = geo.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: height)

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, width * fraction), height: height)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging { isDragging = true }
                        let frac = min(max(drag.location.x / width, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        value = range.lowerBound + frac * span
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: isDragging)
        }
    }
}

// MARK: - Volume Slider

private struct VolumeSlider: View {
    @Binding var isDragging: Bool
    @State private var volume: Double = 0
    @State private var observer: VolumeObserver?

    // Hidden MPVolumeView to control system volume
    @State private var volumeView = MPVolumeView(frame: .zero)

    var body: some View {
        CustomSlider(
            value: $volume,
            range: 0...1,
            isDragging: $isDragging,
            trackHeight: 4,
            activeTrackHeight: 8,
            fillColor: Color.secondary,
            onEnded: { isDragging = false }
        )
        .onChange(of: volume) {
            if isDragging {
                setSystemVolume(Float(volume))
            }
        }
        .onAppear {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            volume = Double(session.outputVolume)
            observer = VolumeObserver { newVolume in
                if !isDragging {
                    volume = Double(newVolume)
                }
            }
            #endif
        }
        .background {
            SystemVolumeView(volumeView: volumeView)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    private func setSystemVolume(_ value: Float) {
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }
    }
}

#if os(iOS)
private class VolumeObserver: NSObject {
    private var observation: NSKeyValueObservation?
    private let onChange: (Float) -> Void

    init(onChange: @escaping (Float) -> Void) {
        self.onChange = onChange
        super.init()
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            if let value = change.newValue {
                Task { @MainActor in
                    onChange(value)
                }
            }
        }
    }
}
#endif

// MARK: - UIKit Wrappers

#if os(iOS)
private struct SystemVolumeView: UIViewRepresentable {
    let volumeView: MPVolumeView

    func makeUIView(context: Context) -> MPVolumeView {
        volumeView.showsRouteButton = false
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct AirPlayButton: UIViewRepresentable {
    var activeTintColor: UIColor = .tintColor
    var routeActive: Bool = false

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = routeActive ? activeTintColor : .secondaryLabel
        view.activeTintColor = activeTintColor
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = routeActive ? activeTintColor : .secondaryLabel
        uiView.activeTintColor = activeTintColor
    }
}

/// Invisible AVRoutePickerView that fills its frame — tapping anywhere opens the picker.
private struct AirPlayTapArea: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .clear
        view.activeTintColor = .clear
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
