import Foundation
import Testing
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import MusicBox

/// The login screen's branding is an asset looked up by name, so renaming or dropping it
/// breaks the screen silently — nothing fails to compile.
struct AppIconImageTests {

    @Test func artworkIsInTheBundle() {
        #if os(iOS)
        #expect(UIImage(named: "AppIconArtwork") != nil)
        #else
        #expect(NSImage(named: "AppIconArtwork") != nil)
        #endif
    }
}
