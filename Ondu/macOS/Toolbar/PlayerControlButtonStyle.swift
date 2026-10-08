#if os(macOS)
import SwiftUI

/// Hover and pressed states for the player row's controls.
///
/// `.plain` strips the hover highlight along with the bezel, which left the row reading
/// as static glyphs rather than buttons. Music.app highlights each control under the
/// cursor and deepens it on press — this restores both without the permanent bezel a
/// bordered style would draw. Applied once to the row so every control agrees.
struct PlayerControlButtonStyle: ButtonStyle {
    /// Off for the volume icons: Music.app leaves those bare and simply brightens them
    /// under the cursor, so a filled rectangle around each one reads as too much.
    var showsBackground = true

    func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration, showsBackground: showsBackground)
    }

    private struct Highlight: View {
        let configuration: Configuration
        let showsBackground: Bool
        /// A disabled control shouldn't invite a click it won't honour.
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                // The glyph is much smaller than its frame, and without this only the
                // glyph itself would take the hover and the click.
                .contentShape(Rectangle())
                .background {
                    if showsBackground {
                        RoundedRectangle(cornerRadius: playerControlCornerRadius)
                            .fill(Color.primary.opacity(fillOpacity))
                    }
                }
                // A custom ButtonStyle draws the label exactly as given, so the dimming
                // `.plain` used to apply to disabled buttons has to be done here — without
                // it a skip button with nothing to skip to looked perfectly clickable.
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { isHovering = $0 }
                // A custom ButtonStyle replaces .plain wholesale, and the dimming of
                // disabled controls went with it — previous/next with nothing to skip to
                // looked identical to live ones.
                .opacity(isEnabled ? 1 : 0.35)
        }

        private var fillOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.16 }
            return isHovering ? 0.08 : 0
        }
    }
}

/// The volume icons, which brighten instead of gaining a background.
struct VolumeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Brighten(configuration: configuration)
    }

    private struct Brighten: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .foregroundStyle(isHovering || configuration.isPressed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { isHovering = $0 }
                // A custom ButtonStyle replaces .plain wholesale, and the dimming of
                // disabled controls went with it — previous/next with nothing to skip to
                // looked identical to live ones.
                .opacity(isEnabled ? 1 : 0.35)
        }
    }
}

/// Rounded enough to read as a control at 34pt without becoming a pill.
let playerControlCornerRadius: CGFloat = 6

#endif
