#if os(macOS)
import SwiftUI

/// The spacing scale for the content views.
///
/// Before this they ran 3/6/8/12/14/16/18/20/24 with nothing behind the choice — each
/// number was picked where it was written. The names say what a gap is *for*, so a new
/// view picks by intent rather than by copying whatever the file next to it did.
///
/// The player row and the mini player are deliberately outside this: their numbers were
/// measured against Music.app and snapping them to a scale would undo that.
enum Spacing {
    /// A label and the thing it labels.
    static let tight: CGFloat = 4
    /// Controls that belong to each other in a row.
    static let related: CGFloat = 8
    /// Distinct elements inside one block.
    static let element: CGFloat = 12
    /// A block's own padding.
    static let block: CGFloat = 16
    /// A page's margin. Also the album grid's section inset, so a cover doesn't move
    /// when you open it.
    static let page: CGFloat = 20
    /// Between the major sections of a page.
    static let section: CGFloat = 32
}
#endif
