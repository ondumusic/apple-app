#if os(macOS)
import AppKit
import SwiftUI

/// Fades chrome while the app isn't frontmost, the way AppKit does for its own controls.
///
/// Two earlier attempts missed. SwiftUI's `controlActiveState` reads `.inactive` inside
/// toolbar items even when the window has focus, so anything keyed off it sat permanently
/// in its inactive branch. Setting `foregroundStyle` on a group of buttons doesn't reach
/// their glyphs either — the button style paints its label itself. Opacity applies to the
/// rendered result, so nothing downstream can override it.
private struct InactiveFade: ViewModifier {
    @State private var isActive = NSApp?.isActive ?? true

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0.45)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)
            ) { _ in isActive = true }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didResignActiveNotification)
            ) { _ in isActive = false }
    }
}

extension View {
    func fadesWhenInactive() -> some View { modifier(InactiveFade()) }
}
#endif
