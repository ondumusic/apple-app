#if os(macOS)
import AppKit
import SwiftUI

/// Whether the app is frontmost, for chrome that has to grey itself out.
///
/// SwiftUI's `controlActiveState` reads `.inactive` inside toolbar items even when the
/// window has focus, so anything keyed off it was permanently in its inactive branch —
/// which is why the scrubber went grey and the controls never changed. NSApplication's
/// own notifications are the reliable signal.
@Observable
final class AppActivity {
    static let shared = AppActivity()

    private(set) var isActive: Bool = NSApp?.isActive ?? true

    private init() {
        for (name, active) in [(NSApplication.didBecomeActiveNotification, true),
                               (NSApplication.didResignActiveNotification, false)] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.isActive = active }
            }
        }
    }
}
#endif
