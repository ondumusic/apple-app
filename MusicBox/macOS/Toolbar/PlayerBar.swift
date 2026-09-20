#if os(macOS)
import SwiftUI

/// The player row, as ordinary content at the top of the detail column.
///
/// Not toolbar items: those are an overflow model, so controls get pushed into a `»`
/// menu long before the space actually runs out. Music.app doesn't use them either —
/// inspecting its window shows the transport, the LCD and the right-hand controls as
/// plain subviews inside its split view, with no toolbar anywhere.
struct PlayerBar: View {
    static let height: CGFloat = 52

    @Environment(PlayerService.self) private var player
    @Binding var showQueue: Bool

    @State private var width: CGFloat = 0

    /// Measured from Music.app at four window widths: its LCD is 40% of the content
    /// column, capped at 900, and its centre sits a constant 22.5pt left of the column's
    /// centre at every width — 1199/337/480, 1799/517/720, 2399/727/900, 2607/831/900.
    /// The cap is what stops it growing absurdly on a wide display; ours was 620, which
    /// is why the balance broke long before Music's did.
    private static let displayCap: CGFloat = 900
    private static let centreOffset: CGFloat = 22.5

    private var displayWidth: CGFloat {
        guard width > 0 else { return 320 }
        return max(200, min(Self.displayCap, width * 0.40))
    }

    /// Everything to the left of the display, exactly as Music does it — the transport
    /// group isn't a fixed proportion, it's the leftover, which is why the space around
    /// the controls keeps growing after the display stops. Reproduces their numbers to
    /// the point: 337.7, 517.7, 727.5 against their 337, 517, 727.
    private var transportWidth: CGFloat {
        guard width > 0 else { return 240 }
        let leftover = width / 2 - Self.centreOffset - displayWidth / 2
        return max(playerControlSize * 5, leftover)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ShuffleButton()
                TransportButtons()
                RepeatButton()
            }
            .frame(width: transportWidth)

            NowPlayingLabel()
                .frame(width: displayWidth)

            Spacer(minLength: 16)

            HStack(spacing: 2) {
                VolumeSlider()
                AirPlayControl()
                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14))
                        .frame(width: playerControlSize, height: playerControlSize)
                        .foregroundStyle(showQueue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .help("Up Next")
                .accessibilityLabel("Up Next")
                .disabled(player.currentTrack == nil)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // As ordinary content the row has to ask for what a toolbar's hosting view used
        // to supply. Not `.plain`: that drops the hover highlight too, and these read as
        // buttons in Music.app.
        .buttonStyle(PlayerControlButtonStyle())
        .fadesWhenInactive()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
/// AirPlay, with the row's hover treatment. Its own view reports the hover, since the
/// AppKit picker inside swallows SwiftUI's.
private struct AirPlayControl: View {
    @State private var isHovering = false

    var body: some View {
        AirPlayPicker(
            controlSize: playerControlSize,
            onHoverChange: { isHovering = $0 }
        )
        .frame(width: playerControlSize, height: playerControlSize)
        .background {
            RoundedRectangle(cornerRadius: playerControlCornerRadius)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
        }
        .help("AirPlay")
    }
}
#endif
