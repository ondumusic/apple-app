#if os(macOS)
import AVKit
import SwiftUI

/// AVRoutePickerView is an NSView on macOS, so the same output picker the iOS player
/// uses works here — no separate device-switching UI to build.
struct AirPlayPicker: NSViewRepresentable {
    var size: CGFloat = 20
    /// Outer hit and hover area. Defaults to the glyph, which is what the mini player
    /// wants; the player row passes the shared control size so its highlight matches the
    /// buttons beside it.
    var controlSize: CGFloat?
    /// The active colour is the system accent by default, which is a fixed blue that
    /// ignores both the app accent and whatever the surface underneath happens to be.
    var normalColor: NSColor = .secondaryLabelColor
    var activeColor: NSColor = .controlAccentColor
    /// AVRoutePickerView has its own tracking, which swallows SwiftUI's `.onHover` — a
    /// hover background on the wrapper never lit up. Reporting it from inside is the way
    /// to have this one control behave like the rest of the row.
    var onHoverChange: ((Bool) -> Void)?

    private var outerSize: CGFloat { controlSize ?? size }

    func makeNSView(context: Context) -> HoverReportingView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(normalColor, for: .normal)
        picker.setRoutePickerButtonColor(activeColor, for: .active)
        picker.setAccessibilityLabel("AirPlay")
        picker.translatesAutoresizingMaskIntoConstraints = false

        let container = HoverReportingView()
        container.onHoverChange = onHoverChange
        container.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            picker.widthAnchor.constraint(equalToConstant: size),
            picker.heightAnchor.constraint(equalToConstant: size),
        ])
        return container
    }

    func updateNSView(_ nsView: HoverReportingView, context: Context) {
        nsView.onHoverChange = onHoverChange
        guard let picker = nsView.subviews.first as? AVRoutePickerView else { return }
        picker.setRoutePickerButtonColor(normalColor, for: .normal)
        picker.setRoutePickerButtonColor(activeColor, for: .active)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HoverReportingView, context: Context) -> CGSize {
        CGSize(width: outerSize, height: outerSize)
    }
}

/// Reports hover out to SwiftUI. The picker stays a subview, so clicks still reach it.
final class HoverReportingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
#endif
