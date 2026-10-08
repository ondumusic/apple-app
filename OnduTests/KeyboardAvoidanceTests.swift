#if os(iOS)
import Testing
import CoreGraphics
@testable import Ondu

struct KeyboardAvoidanceTests {
    // iPhone-ish geometry: content fills the screen above a tab bar.
    private let content = CGRect(x: 0, y: 0, width: 390, height: 761)

    @Test func hiddenKeyboardHasNoOverlap() {
        #expect(KeyboardAvoidance.overlap(contentFrame: content, keyboardFrame: nil) == 0)
    }

    @Test func dockedKeyboardOverlapsByCoveredHeight() {
        let keyboard = CGRect(x: 0, y: 508, width: 390, height: 336)
        #expect(KeyboardAvoidance.overlap(contentFrame: content, keyboardFrame: keyboard) == 253)
    }

    @Test func offscreenEndFrameHasNoOverlap() {
        // Hide animation reports an end frame below the screen.
        let keyboard = CGRect(x: 0, y: 844, width: 390, height: 336)
        #expect(KeyboardAvoidance.overlap(contentFrame: content, keyboardFrame: keyboard) == 0)
    }

    @Test func keyboardBelowContentHasNoOverlap() {
        let keyboard = CGRect(x: 0, y: 761, width: 390, height: 83)
        #expect(KeyboardAvoidance.overlap(contentFrame: content, keyboardFrame: keyboard) == 0)
    }

    @Test func floatingKeyboardIsIgnored() {
        let keyboard = CGRect(x: 20, y: 400, width: 320, height: 260)
        let pane = CGRect(x: 0, y: 0, width: 390, height: 761)
        #expect(KeyboardAvoidance.overlap(contentFrame: pane, keyboardFrame: keyboard) == 0)
    }

    @Test func splitViewPaneNarrowerThanKeyboardStillInsets() {
        let keyboard = CGRect(x: 0, y: 700, width: 1180, height: 320)
        let pane = CGRect(x: 590, y: 0, width: 590, height: 1020)
        #expect(KeyboardAvoidance.overlap(contentFrame: pane, keyboardFrame: keyboard) == 320)
    }
}
#endif
