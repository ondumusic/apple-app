import SwiftUI

/// The app's own icon, for chrome that has to say what the app is — the login screen
/// has nothing else to identify itself with.
///
/// Its own copy of the artwork rather than the installed icon, because neither platform
/// will hand that over at a useful size: it's compiled as the bundle's icon rather than
/// as an ordinary image asset, so `Image("AppIcon")` finds nothing, and what iOS does
/// leave reachable is a 120px file that upscales visibly at any size worth showing.
///
/// Only the light appearance is exported. The icon's dark and tinted variants are for
/// the home screen, where it sits on the user's wallpaper; here it sits on our own
/// background, where it doesn't need to adapt. Exported at 512px — several times what
/// anything draws it at, and a tenth of the weight of the 1024 master. Re-export from
/// Icon Composer when the icon changes.
struct AppIconImage: View {
    var size: CGFloat = 52

    var body: some View {
        // Already carries the icon's shape, so it isn't clipped again.
        Image("AppIconArtwork")
            .resizable()
            .frame(width: size, height: size)
    }
}
