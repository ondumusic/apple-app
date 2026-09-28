import SwiftUI

/// The app's own icon, for chrome that has to say what the app is — the login screen
/// has nothing else to identify itself with.
///
/// Neither platform looks an app icon up by name. It's compiled as the bundle's icon
/// rather than as an ordinary image asset, so `Image("AppIcon")` finds nothing. macOS
/// has an API that hands it over; iOS doesn't, so the filename has to come from
/// Info.plist. Reading it there rather than hardcoding it is also what keeps this
/// working when the icon is renamed, which the debug build's is meant to be.
struct AppIconImage: View {
    var size: CGFloat = 52

    var body: some View {
        #if os(macOS)
        // Not NSApplication.applicationIconImage: that answers with a single flattened
        // 128px representation, where the named lookup returns the icon with all of its
        // sizes and stays sharp at whatever this is drawn at. Either way it already
        // carries the icon's shape and shadow, so it must not be clipped again.
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        }
        #else
        if let name = Self.bundledIconName, let icon = UIImage(named: name) {
            Image(uiImage: icon)
                .resizable()
                .frame(width: size, height: size)
                // What ships in the bundle is the unmasked square: the home screen
                // applies the shape, and nothing does it for us here. 0.2237 of the
                // width is the ratio Apple's own icon grid uses.
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        }
        #endif
    }

    #if os(iOS)
    /// The largest icon this build actually shipped, whatever it ended up called.
    static var bundledIconName: String? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String]
        else { return nil }
        return files.last
    }
    #endif
}
