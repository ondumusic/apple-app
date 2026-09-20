#if os(macOS)
import AppKit
import SwiftUI

/// The draggable divider between sidebar and content.
///
/// Hand-rolled because the window has no NavigationSplitView to provide one — that's
/// what was installing a toolbar and forcing the player into an overflow model. This is
/// the only piece of the split view we actually used: the sidebar is never collapsible
/// here, so there is nothing else to reimplement.
struct SidebarDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>

    @State private var widthAtDragStart: Double?

    var body: some View {
        Divider()
            // A hairline is too thin to grab; Finder's divider has a wider hit area than
            // it draws, so the visible line stays 1pt and the target is 8.
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = widthAtDragStart ?? width
                                if widthAtDragStart == nil { widthAtDragStart = start }
                                width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in widthAtDragStart = nil }
                    )
            }
    }
}
#endif
