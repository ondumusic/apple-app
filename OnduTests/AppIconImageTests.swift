import Foundation
import Testing

@testable import Ondu

#if os(iOS)
import UIKit
#else
import AppKit
#endif

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
