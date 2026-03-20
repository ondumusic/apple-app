#if os(iOS)
import UIKit
#endif

nonisolated enum Haptics {
    @MainActor static var isEnabled: Bool = true

    static func light() {
        #if os(iOS)
        guard MainActor.assumeIsolated({ isEnabled }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if os(iOS)
        guard MainActor.assumeIsolated({ isEnabled }) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func selection() {
        #if os(iOS)
        guard MainActor.assumeIsolated({ isEnabled }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
