#if os(macOS)
import AppKit
import SwiftUI

struct AboutButton: View {
    var body: some View {
        Button("About \(AboutPanel.appName)") { AboutPanel.show() }
    }
}

enum AboutPanel {
    /// The bundle's name rather than a literal, so a Debug build says "Ondu Dev" the way
    /// the panel itself and the menu bar do.
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Ondu"
    }

    static func show() {
        let link = NSAttributedString(
            string: SiteLinks.website.host() ?? SiteLinks.website.absoluteString,
            attributes: [
                .link: SiteLinks.website,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ])
        let credits = NSMutableAttributedString(attributedString: link)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
#endif
