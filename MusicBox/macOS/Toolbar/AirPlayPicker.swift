#if os(macOS)
import AVKit
import SwiftUI

/// AVRoutePickerView is an NSView on macOS, so the same output picker the iOS player
/// uses works here — no separate device-switching UI to build.
struct AirPlayPicker: NSViewRepresentable {
    var size: CGFloat = 20

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
        view.setRoutePickerButtonColor(.controlAccentColor, for: .active)
        view.setAccessibilityLabel("AirPlay")
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVRoutePickerView, context: Context) -> CGSize {
        CGSize(width: size, height: size)
    }
}
#endif
