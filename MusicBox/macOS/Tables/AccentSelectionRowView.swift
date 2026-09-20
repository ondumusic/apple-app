#if os(macOS)
import AppKit

/// Table row that paints its own selection pill in the app accent. Every AppKit table in
/// the app uses it: NSTableView draws `.regular` and `.sourceList` selection itself and
/// never delegates to a row view, so both would paint the system accent over anything we
/// draw — the tables set `selectionHighlightStyle = .none` and hand the job here.
final class AccentSelectionRowView: NSTableRowView {
    /// Set by the delegate to skip the bottom hairline. Used for the final row,
    /// section-header rows, and rows immediately above section headers — wherever the
    /// divider would clash with the table's grouping or the row below.
    var suppressDivider: Bool = false

    /// See DragVisibleView: AppKit hides a drag's source rows for its duration, which
    /// leaves gaps in the table. Declining the hide is the only flash-free way — undoing
    /// it afterwards is always a frame late.
    var suppressesHiding = false {
        // Clearing on the way in matters: AppKit may already have hidden the row by the
        // time the drag session reports itself, and the override below only blocks
        // *new* attempts.
        didSet { if suppressesHiding { isHidden = false } }
    }

    override var isHidden: Bool {
        get { super.isHidden }
        set {
            guard !(suppressesHiding && newValue) else { return }
            super.isHidden = newValue
        }
    }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set { /* ignore — pinned to .none so NSTableView's right-click target ring
              doesn't paint a full-row outline ignoring our custom selection bounds. */ }
    }

    override var isSelected: Bool {
        get { super.isSelected }
        set {
            super.isSelected = newValue
            // Propagate emphasis to cells synchronously, before the pending row redraw,
            // so cells' text flips to white in the same frame the pill appears (no flash
            // from black to white during shift-range selection).
            applyCellEmphasis()
            // Redraw in the same pass. Without this the pill waits for the delegate's
            // selection-changed sweep, so a deselected row's text went black while its
            // pill was still painted — visible as a flash on every click.
            needsDisplay = true
        }
    }
    /// When non-nil, NSTableView's native source-list selection pill is replaced with
    /// a custom one that starts `customSelectionLeftInset` from the leading edge —
    /// used in sections mode so the pill doesn't extend behind the artwork overlay.
    var customSelectionLeftInset: CGFloat? = nil
    /// Trailing inset used with `customSelectionLeftInset`. Mirrors source-list's ~16pt
    /// trailing inset so the pill ends symmetrically.
    var customSelectionRightInset: CGFloat = 16
    /// The app accent rather than NSColor.selectedContentBackgroundColor, which follows
    /// the system accent and left selection disagreeing with the rest of the UI.
    var selectionColor: NSColor = .selectedContentBackgroundColor

    /// macOS greys out selection in a window that isn't key — ours stayed at full accent,
    /// which made an inactive window read as if it still had focus. Cells follow: the
    /// system keeps label text primary against the unemphasized fill rather than white.
    private var isWindowActive: Bool { window?.isKeyWindow ?? false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Sync to the window's *current* state, not just to later changes. Cells are
        // often built before the row is in a window at all — every launch, since the
        // selection is restored first — and with only change-observation nothing ever
        // corrected the mismatch: an accent pill drawn later under text coloured for a
        // window that wasn't key yet.
        applyCellEmphasis()
        needsDisplay = true
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.applyCellEmphasis()
                    self.needsDisplay = true
                }
            })
        }
    }

    private var keyObservers: [NSObjectProtocol] = []

    deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }
    /// Standalone tables use alternating row colours, which NSTableRowView paints in its
    /// own drawBackground — our override has to defer to it or the stripes disappear.
    var drawsRowBackground: Bool = false

    override func drawBackground(in dirtyRect: NSRect) {
        if drawsRowBackground {
            super.drawBackground(in: dirtyRect)
        }
        // Custom selection pill — drawn in drawBackground because NSTableView's selection
        // rendering happens at the table level (not delegated to the row's drawSelection)
        // for both .regular and .sourceList highlight styles. We rely on selectionHighlight
        // Style = .none on the table so nothing else paints over us.
        if isSelected, let leftInset = customSelectionLeftInset {
            drawCustomSelectionPill(leftInset: leftInset)
        }
        // Inter-row hairline. Skipped on suppressed rows, selected rows, and rows above
        // a selected row so the pill stays clean.
        guard !suppressDivider, !isSelected, !isNextRowSelected else { return }
        let line = NSRect(x: bounds.minX + 8,
                          y: bounds.maxY - 0.5,
                          width: bounds.width - 16,
                          height: 0.5)
        NSColor.separatorColor.setFill()
        line.fill()
    }

    /// Tables that draw their own hairline in drawBackground suppress this entirely;
    /// ones relying on NSTableView's grid lines opt back in.
    var drawsSystemSeparator: Bool = false

    override func drawSeparator(in dirtyRect: NSRect) {
        guard drawsSystemSeparator else { return }
        super.drawSeparator(in: dirtyRect)
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        // Standalone tables support drag-to-reorder (playlists), so they need the drop
        // indicator; embedded ones don't reorder and suppressed it deliberately.
        guard drawsRowBackground else { return }
        super.drawDraggingDestinationFeedback(in: dirtyRect)
    }

    /// Replace the default draw pipeline (which paints a full-row context-menu outline
    /// when right-clicked) with just our background. Selection drawing is handled inside
    /// drawBackground; other phases are no-ops above.
    override func draw(_ dirtyRect: NSRect) {
        if drawsRowBackground {
            // Full pipeline: our drawBackground paints the pill, super handles the rest.
            super.draw(dirtyRect)
        } else {
            drawBackground(in: dirtyRect)
        }
    }

    /// Cells consult their row view's `interiorBackgroundStyle` to choose text colors.
    /// With selectionHighlightStyle = .none, the default returns `.normal` even when
    /// the row is selected — so cells draw black text. Override to surface the
    /// emphasized state when the row carries a custom inset (sections mode).
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        if isSelected && customSelectionLeftInset != nil {
            return .emphasized
        }
        return super.interiorBackgroundStyle
    }

    private func applyCellEmphasis() {
        let style: NSView.BackgroundStyle = (isSelected && isWindowActive) ? .emphasized : .normal
        for col in 0..<numberOfColumns {
            if let cell = view(atColumn: col) as? NSTableCellView, cell.backgroundStyle != style {
                cell.backgroundStyle = style
            }
        }
    }

    private func drawCustomSelectionPill(leftInset: CGFloat) {
        let radius: CGFloat = 6
        let topRadius: CGFloat = isPreviousRowSelected ? 0 : radius
        let bottomRadius: CGFloat = isNextRowSelected ? 0 : radius
        let rect = NSRect(
            x: bounds.minX + leftInset,
            y: bounds.minY,
            width: max(0, bounds.width - leftInset - customSelectionRightInset),
            height: bounds.height
        )
        guard rect.width > 0 else { return }
        let path = roundedRectPath(rect, topRadius: topRadius, bottomRadius: bottomRadius)
        (isWindowActive ? selectionColor : .unemphasizedSelectedContentBackgroundColor).setFill()
        path.fill()
    }

    /// Rounded-rect with selectable corner radii on top/bottom — uses `appendArc(from:to:)`
    /// so the geometry is correct in either flipped or non-flipped coordinate systems.
    private func roundedRectPath(_ rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        path.move(to: NSPoint(x: minX + topRadius, y: minY))
        path.line(to: NSPoint(x: maxX - topRadius, y: minY))
        if topRadius > 0 {
            path.appendArc(from: NSPoint(x: maxX, y: minY),
                           to: NSPoint(x: maxX, y: minY + topRadius),
                           radius: topRadius)
        }
        path.line(to: NSPoint(x: maxX, y: maxY - bottomRadius))
        if bottomRadius > 0 {
            path.appendArc(from: NSPoint(x: maxX, y: maxY),
                           to: NSPoint(x: maxX - bottomRadius, y: maxY),
                           radius: bottomRadius)
        }
        path.line(to: NSPoint(x: minX + bottomRadius, y: maxY))
        if bottomRadius > 0 {
            path.appendArc(from: NSPoint(x: minX, y: maxY),
                           to: NSPoint(x: minX, y: maxY - bottomRadius),
                           radius: bottomRadius)
        }
        path.line(to: NSPoint(x: minX, y: minY + topRadius))
        if topRadius > 0 {
            path.appendArc(from: NSPoint(x: minX, y: minY),
                           to: NSPoint(x: minX + topRadius, y: minY),
                           radius: topRadius)
        }
        path.close()
        return path
    }
}
#endif
