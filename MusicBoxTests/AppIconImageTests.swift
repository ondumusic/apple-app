import Foundation
import Testing
#if os(iOS)
import UIKit
#endif
@testable import MusicBox

/// The login screen's branding hangs off a name read out of Info.plist, so a build that
/// renames or drops the icon breaks it silently — nothing fails to compile.
struct AppIconImageTests {

    #if os(iOS)
    @Test func bundledIconResolves() throws {
        let name = try #require(AppIconImage.bundledIconName)
        #expect(UIImage(named: name) != nil)
    }
    #endif
}
