import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

nonisolated extension PlatformColor {
    /// A colour from sRGB components, spelled the same on both platforms.
    static func srgb(_ red: Double, _ green: Double, _ blue: Double) -> PlatformColor {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }
}

nonisolated extension Color {
    /// A colour that answers differently in light and dark.
    ///
    /// SwiftUI has no literal for this — an asset catalogue colour set or a platform
    /// colour with a dynamic provider are the two ways, and a colour defined next to the
    /// code that uses it beats one defined in a file nobody opens.
    init(light: PlatformColor, dark: PlatformColor) {
        #if os(macOS)
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        #else
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        #endif
    }
}
