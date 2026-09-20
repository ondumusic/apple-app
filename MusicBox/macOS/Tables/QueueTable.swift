#if os(macOS)
import AppKit
import Nuke
import SwiftUI

/// AppKit-backed Up Next list.
///
/// The SwiftUI version gave every row its own `.draggable` and `.dropDestination`, which
/// is expensive enough to rebuild that a reorder visibly hitched on release — measured:
/// the model work at the drop was ~0.1ms, so the time was all in the list. It also had no
/// way to accept a track or album dragged in from the library, because the drag sources
/// are AppKit and speak NSPasteboard while a SwiftUI drop destination speaks Transferable.
/// An NSTableView is on the same side of that divide, and gives insertion-point drops,
/// reordering and multi-select without any of it being rebuilt per change.
struct QueueTable: NSViewControllerRepresentable {
    let items: [QueueItem]
    let rowHeight: CGFloat
    let showsDuration: Bool
    let accent: Color
    let actions: QueueActions
    /// Matched to the panel's own header padding — the window's is 16, the mini player's
    /// 12 — so the artwork lines up under the "Up Next" title in both.
    var horizontalInset: CGFloat = 16
    /// Sized against the row so the gap above and below stays even; a fixed size looked
    /// cramped in the mini player's shorter rows.
    var artworkSize: CGFloat = 34

    func makeNSViewController(context: Context) -> QueueTableViewController {
        let vc = QueueTableViewController()
        apply(to: vc)
        return vc
    }

    func updateNSViewController(_ vc: QueueTableViewController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: QueueTableViewController) {
        vc.accentNSColor = NSColor(accent)
        vc.actions = actions
        vc.showsDuration = showsDuration
        vc.rowHeightValue = rowHeight
        vc.metrics = QueueCellMetrics(horizontalInset: horizontalInset, artworkSize: artworkSize)
        vc.apply(items: items)
    }
}

final class QueueTableViewController: NSViewController {
    fileprivate var items: [QueueItem] = []
    var actions = QueueActions()
    var showsDuration = true
    var metrics = QueueCellMetrics(horizontalInset: 16, artworkSize: 34)
    var rowHeightValue: CGFloat = 52 {
        didSet {
            guard rowHeightValue != oldValue, isViewLoaded else { return }
            tableView.rowHeight = rowHeightValue
        }
    }
    var accentNSColor: NSColor = .controlAccentColor {
        didSet {
            guard accentNSColor != oldValue, isViewLoaded else { return }
            tableView.enumerateAvailableRowViews { rowView, _ in
                (rowView as? AccentSelectionRowView)?.selectionColor = accentNSColor
                rowView.needsDisplay = true
            }
        }
    }

    private let tableView = QueueKeyTableView()
    private let scrollView = NSScrollView()

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("queue"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        // .plain, not .inset: the inset style adds its own horizontal padding on top of
        // the cell's, which put the artwork at 30pt from the panel edge against the
        // header's 16 and made the panel look over-padded on both sides.
        tableView.style = .plain
        // .none so AccentSelectionRowView paints the accent pill, as every other table
        // in the app does.
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = rowHeightValue
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        // The table still insets its cells a little of its own accord; zeroing this and
        // measuring what's left is what lets the artwork line up with the header.
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.onDelete = { [weak self] in self?.removeSelected() }

        // A gap feedback style is what draws the insertion point between rows, which is
        // the whole reason a drop can land at a position rather than just "in the list".
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.registerForDraggedTypes([.musicBoxQueueRows, .musicBoxTracks, .musicBoxAlbums])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.addBottomContentPadding()
        view = scrollView
    }

    func apply(items newItems: [QueueItem]) {
        let changed = items.map(\.id) != newItems.map(\.id)
        items = newItems
        if changed { tableView.reloadData() }
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        actions.play(row)
    }

    private func removeSelected() {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return }
        actions.remove(rows)
    }

    fileprivate func remove(row: Int) {
        // A remove button on a row that's part of the selection takes the selection.
        if tableView.selectedRowIndexes.contains(row) {
            actions.remove(tableView.selectedRowIndexes)
        } else {
            actions.remove(IndexSet(integer: row))
        }
    }
}

extension QueueTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard items.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .musicBoxQueueRows)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        // Only between rows: dropping *on* a row has no meaning in a queue.
        guard dropOperation == .above else { return [] }
        let types = info.draggingPasteboard.types ?? []
        if types.contains(.musicBoxQueueRows) { return .move }
        if types.contains(.musicBoxTracks) || types.contains(.musicBoxAlbums) { return .copy }
        return []
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let pasteboardItems = info.draggingPasteboard.pasteboardItems ?? []

        let movedRows = pasteboardItems.compactMap { $0.string(forType: .musicBoxQueueRows).flatMap(Int.init) }
        if !movedRows.isEmpty {
            actions.move(IndexSet(movedRows), row)
            return true
        }

        let albumIds = pasteboardItems.compactMap { $0.string(forType: .musicBoxAlbums).flatMap(UUID.init) }
        if !albumIds.isEmpty {
            actions.insertAlbums(albumIds, row)
            return true
        }

        let trackIds = pasteboardItems.compactMap { $0.string(forType: .musicBoxTracks).flatMap(UUID.init) }
        guard !trackIds.isEmpty else { return false }
        actions.insertTracks(trackIds, row)
        return true
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        for row in rowIndexes {
            (tableView.rowView(atRow: row, makeIfNecessary: false) as? AccentSelectionRowView)?
                .suppressesHiding = true
        }
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? AccentSelectionRowView)?.suppressesHiding = false
            rowView.isHidden = false
        }
    }
}

extension QueueTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let cell = tableView.makeView(withIdentifier: QueueCell.identifier, owner: self) as? QueueCell
            ?? QueueCell()
        cell.showsDuration = showsDuration
        cell.metrics = metrics
        cell.onRemove = { [weak self] in self?.remove(row: row) }
        cell.configure(item: items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = AccentSelectionRowView()
        view.selectionColor = accentNSColor
        view.customSelectionLeftInset = 8
        view.customSelectionRightInset = 8
        // Starts where the title does, clear of the artwork — the same treatment
        // Music.app gives its Up Next rows, and what the other tables here already do
        // for rows that have no leading accessory.
        view.suppressDivider = false
        view.dividerLeadingInset = metrics.horizontalInset + metrics.artworkSize + 10
        view.dividerTrailingInset = metrics.horizontalInset
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // selectionHighlightStyle = .none means the table won't redraw rows itself.
        tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
    }
}

/// Delete removes the selection, and the queue is the one list where that needs no
/// confirmation — the track stays in the library.
final class QueueKeyTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let deleteKeys: Set<UInt16> = [51, 117]
        if deleteKeys.contains(event.keyCode) {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}
/// Artwork, title and artist, with the duration giving way to a remove button on hover.
/// Plain AppKit rather than a hosted SwiftUI row: one hosting view per row is what the
/// SwiftUI list was already paying for.
final class QueueCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("QueueCell")

    var showsDuration = true
    var onRemove: (() -> Void)?
    var metrics = QueueCellMetrics(horizontalInset: 16, artworkSize: 34) {
        didSet {
            guard metrics != oldValue else { return }
            applyMetrics()
        }
    }

    private let artwork = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let artist = NSTextField(labelWithString: "")
    private let duration = NSTextField(labelWithString: "")
    private let removeButton = NSButton()
    private var loadingURL: URL?
    private var imageTask: ImageTask?
    private var trackingArea: NSTrackingArea?
    private var artworkLeading: NSLayoutConstraint!
    private var artworkWidth: NSLayoutConstraint!
    private var artworkHeight: NSLayoutConstraint!
    private var durationTrailing: NSLayoutConstraint!
    private var removeTrailing: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func build() {
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 3
        artwork.layer?.masksToBounds = true
        addSubview(artwork)

        title.translatesAutoresizingMaskIntoConstraints = false
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(title)

        artist.translatesAutoresizingMaskIntoConstraints = false
        artist.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        artist.textColor = .secondaryLabelColor
        artist.lineBreakMode = .byTruncatingTail
        artist.cell?.usesSingleLineMode = true
        artist.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(artist)

        duration.translatesAutoresizingMaskIntoConstraints = false
        duration.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        duration.textColor = .secondaryLabelColor
        // Without these the title wins the horizontal argument and runs over the
        // duration rather than truncating against it.
        duration.setContentCompressionResistancePriority(.required, for: .horizontal)
        duration.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(duration)

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isBordered = false
        removeButton.bezelStyle = .inline
        removeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: NSLocalizedString("Remove from queue", comment: "")
        )
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(handleRemove)
        removeButton.isHidden = true
        removeButton.toolTip = NSLocalizedString("Remove from queue", comment: "")
        addSubview(removeButton)

        artworkLeading = artwork.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.horizontalInset)
        artworkWidth = artwork.widthAnchor.constraint(equalToConstant: metrics.artworkSize)
        artworkHeight = artwork.heightAnchor.constraint(equalToConstant: metrics.artworkSize)
        durationTrailing = duration.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -metrics.horizontalInset)
        removeTrailing = removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(metrics.horizontalInset - 2))

        NSLayoutConstraint.activate([
            artworkLeading,
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkWidth,
            artworkHeight,

            title.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: duration.leadingAnchor, constant: -8),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),

            artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            artist.trailingAnchor.constraint(lessThanOrEqualTo: duration.leadingAnchor, constant: -8),
            artist.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),

            durationTrailing,
            duration.centerYAnchor.constraint(equalTo: centerYAnchor),

            removeTrailing,
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func applyMetrics() {
        artworkLeading.constant = metrics.horizontalInset
        artworkWidth.constant = metrics.artworkSize
        artworkHeight.constant = metrics.artworkSize
        durationTrailing.constant = -metrics.horizontalInset
        removeTrailing.constant = -(metrics.horizontalInset - 2)
    }

    func configure(item: QueueItem) {
        title.stringValue = item.track.name
        artist.stringValue = item.track.artist.name
        duration.stringValue = item.track.formattedDuration
        duration.isHidden = !showsDuration
        applyEmphasis()

        guard loadingURL != item.artworkURL else { return }
        imageTask?.cancel()
        loadingURL = item.artworkURL
        artwork.image = nil
        guard let url = item.artworkURL else { return }
        imageTask = ImagePipeline.shared.loadImage(
            with: ImageRequest(url: url, processors: [.resize(width: 80)])
        ) { [weak self] result in
            guard let self, self.loadingURL == url else { return }  // recycled mid-flight
            if case .success(let response) = result { self.artwork.image = response.image }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        loadingURL = nil
        artwork.image = nil
        setHovering(false)
    }

    @objc private func handleRemove() { onRemove?() }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        let emphasized = backgroundStyle == .emphasized
        title.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        let secondary: NSColor = emphasized
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.85)
            : .secondaryLabelColor
        artist.textColor = secondary
        duration.textColor = secondary
        removeButton.contentTintColor = secondary
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    /// The duration gives way to the button rather than sitting beside it, so the row
    /// doesn't reflow on hover.
    private func setHovering(_ hovering: Bool) {
        removeButton.isHidden = !hovering
        duration.isHidden = hovering || !showsDuration
    }
}

/// How a queue row is inset and how big its artwork is. The window's panel and the mini
/// player's differ in both, and a row that ignores that either misaligns with its header
/// or crowds its own artwork.
struct QueueCellMetrics: Equatable {
    var horizontalInset: CGFloat
    var artworkSize: CGFloat
}
#endif
