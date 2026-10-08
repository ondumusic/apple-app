#if os(macOS)
import SwiftUI

/// Starts a real AppKit drag from a SwiftUI view.
///
/// SwiftUI's `.onDrag` advertises its payload through an `NSItemProvider`, and a type
/// identifier the system doesn't know — ours are plain strings, not declared UTIs —
/// reaches the pasteboard as a dynamic type instead. Tables register for the literal
/// string, so AppKit never routes such a drag to them and no drop target is ever asked to
/// validate it: the drag looks fine and the drop silently does nothing. Writing the
/// `NSPasteboardItem` here puts exactly what the AppKit tables put on the pasteboard.
///
/// The handle covers the view and owns its mouse events, so a cell that would otherwise
/// be a `Button` gets its click back through `onClick`.
struct PasteboardDragHandle: NSViewRepresentable {
    let type: NSPasteboard.PasteboardType
    let value: String
    /// The part of the view the drag image is cut from, in SwiftUI's top-left
    /// coordinates. Nil pictures the whole thing — usually too much, since a caption
    /// under a thumbnail reads as a stray rectangle once it's floating under the pointer.
    var dragImageRect: CGRect? = nil
    /// Rounds the drag image. Half its width makes a circle.
    var dragImageCornerRadius: CGFloat = 0
    let onClick: () -> Void

    func makeNSView(context: Context) -> PasteboardDragHandleView {
        let view = PasteboardDragHandleView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PasteboardDragHandleView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: PasteboardDragHandleView) {
        view.pasteboardType = type
        view.value = value
        view.dragImageRect = dragImageRect
        view.dragImageCornerRadius = dragImageCornerRadius
        view.onClick = onClick
    }
}

final class PasteboardDragHandleView: NSView {
    var pasteboardType: NSPasteboard.PasteboardType = .onduArtists
    var value: String = ""
    var dragImageRect: CGRect?
    var dragImageCornerRadius: CGFloat = 0
    var onClick: () -> Void = {}

    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, !value.isEmpty, let start = mouseDownPoint else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        // The same few points of slop AppKit uses, so a click with a shaky hand stays a
        // click.
        guard dx * dx + dy * dy > 9 else { return }
        isDragging = true

        let item = NSPasteboardItem()
        item.setString(value, forType: pasteboardType)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let frame = imageFrame
        dragItem.setDraggingFrame(frame, contents: snapshot(of: frame))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !isDragging else { return }
        onClick()
    }

    /// `dragImageRect` in this view's own coordinates. SwiftUI measures it from the top
    /// edge, AppKit from the bottom.
    private var imageFrame: NSRect {
        guard let rect = dragImageRect else { return bounds }
        return NSRect(x: rect.minX, y: bounds.height - rect.maxY,
                      width: rect.width, height: rect.height)
    }

    /// The drag image, cut out of what is already on screen.
    ///
    /// Rendered from the window's content view rather than our own superview: SwiftUI
    /// draws a plain cell into a shared layer instead of giving it an NSView, so the
    /// content we want to picture is nowhere in this view's own subtree.
    private func snapshot(of frame: NSRect) -> NSImage? {
        guard frame.width > 0, frame.height > 0, let root = window?.contentView else { return nil }
        let inRoot = convert(frame, to: root)
        guard let rep = root.bitmapImageRepForCachingDisplay(in: inRoot) else { return nil }
        root.cacheDisplay(in: inRoot, to: rep)
        let image = NSImage(size: frame.size)
        image.addRepresentation(rep)
        guard dragImageCornerRadius > 0 else { return image }

        // The cell clips its artwork to a circle but the pixels behind it belong to the
        // page, so an unmasked crop drags a square with a circle painted in it.
        let masked = NSImage(size: frame.size)
        let bounds = NSRect(origin: .zero, size: frame.size)
        masked.lockFocus()
        NSBezierPath(roundedRect: bounds,
                     xRadius: dragImageCornerRadius,
                     yRadius: dragImageCornerRadius).addClip()
        image.draw(in: bounds)
        masked.unlockFocus()
        return masked
    }
}

extension PasteboardDragHandleView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
    }
}
#endif
