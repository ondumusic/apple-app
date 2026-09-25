#if os(macOS)
import AppKit

extension NSView {
    /// Takes keyboard focus for the list a section just opened.
    ///
    /// AppKit routes type-select to the first responder. Without this it stayed wherever
    /// it was — the sidebar after a click, or the previous section's list — so typing
    /// searched the wrong table, silently when that table had nothing to match against.
    ///
    /// Deliberately not conditional on what held focus before: gating on "the sidebar has
    /// it" worked when a section was open at launch and failed on every navigation after,
    /// because by then the outgoing section's list held it. The one thing worth
    /// protecting is typing in progress, which is the sidebar's search field or an inline
    /// rename — both field editors.
    ///
    /// Only the lists a sidebar selection opens should call this; see
    /// `TracksTable.claimsKeyboardFocus`.
    func claimKeyboardFocus() {
        guard let window, !(window.firstResponder is NSText), window.firstResponder !== self
        else { return }
        window.makeFirstResponder(self)
    }
}
#endif
