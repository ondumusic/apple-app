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
    /// Off for History, which is a record of what happened rather than a list you
    /// arrange: no reorder, no drops in, no remove button, no Delete key.
    var allowsEditing: Bool = true
    /// Shown centred over the table when there are no rows.
    ///
    /// AppKit rather than a SwiftUI overlay: the panel slides in with a SwiftUI
    /// transition, and a SwiftUI overlay layered on this hosted view didn't ride that
    /// transition — the text arrived at its final position while everything around it
    /// was still moving. Inside the table it can't do anything but move with it.
    var emptyState: QueueEmptyState? = nil

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
        vc.allowsEditing = allowsEditing
        vc.emptyState = emptyState
        vc.apply(items: items)
    }
}

nonisolated struct QueueEmptyState: Equatable, Sendable {
    var title: String?
    var symbol: String?
    var message: String?
}

final class QueueTableViewController: NSViewController {
    fileprivate var items: [QueueItem] = []
    var emptyState: QueueEmptyState? {
        didSet {
            guard emptyState != oldValue, isViewLoaded else { return }
            refreshEmptyState()
        }
    }
    private let emptySymbol = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyMessage = NSTextField(labelWithString: "")
    private lazy var emptyStack: NSStackView = {
        let stack = NSStackView(views: [emptySymbol, emptyTitle, emptyMessage])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        // Never a drop target and never a click target: the table underneath owns both,
        // and an empty queue is exactly when you want to drag something into it.
        stack.isHidden = true
        return stack
    }()
    var actions = QueueActions()
    var allowsEditing: Bool = true {
        didSet {
            guard allowsEditing != oldValue, isViewLoaded else { return }
            applyEditingAffordances()
        }
    }

    private func applyEditingAffordances() {
        if allowsEditing {
            tableView.registerForDraggedTypes([
                .onduQueueRows, .onduTracks, .onduAlbums, .onduArtists,
                .onduSidebarPlaylist,
            ])
        } else {
            tableView.unregisterDraggedTypes()
        }
        tableView.setDraggingSourceOperationMask(allowsEditing ? .move : [], forLocal: true)
    }
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
    private var hoveredRow: Int?
    private var trackingArea: NSTrackingArea?

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
        tableView.onDelete = { [weak self] in
            guard let self, self.allowsEditing else { return }
            self.removeSelected()
        }

        // A gap feedback style is what draws the insertion point between rows, which is
        // the whole reason a drop can land at a position rather than just "in the list".
        tableView.draggingDestinationFeedbackStyle = .gap
        applyEditingAffordances()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.addBottomContentPadding()
        scrollView.contentView.postsBoundsChangedNotifications = true
        emptySymbol.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        emptySymbol.contentTintColor = .tertiaryLabelColor
        emptyTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        emptyTitle.textColor = .secondaryLabelColor
        emptyMessage.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyMessage.textColor = .tertiaryLabelColor
        emptyMessage.alignment = .center
        emptyMessage.lineBreakMode = .byWordWrapping
        emptyMessage.maximumNumberOfLines = 3

        let container = NonInteractiveContainer()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyStack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -32),
        ])
        view = container
        refreshEmptyState()

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        // Scrolling moves rows under a stationary cursor and produces no mouse event of
        // its own, so a per-row tracking area leaves the hover stuck on whichever row
        // the pointer was over when the scroll started.
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHoverFromPointer() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func refreshEmphasis() {
        let selected = tableView.selectedRowIndexes
        for row in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? QueueCell
            else { continue }
            cell.backgroundStyle = selected.contains(row) ? .emphasized : .normal
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let trackingArea { view.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        applyHover(row: tableView.row(at: tableView.convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        applyHover(row: -1)
    }

    /// From the pointer's position rather than an event, for the cases that produce none:
    /// scrolling, and rows being recycled underneath it.
    private func refreshHoverFromPointer() {
        guard let window = view.window, window.isKeyWindow else { return applyHover(row: -1) }
        let local = tableView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard tableView.visibleRect.contains(local) else { return applyHover(row: -1) }
        applyHover(row: tableView.row(at: local))
    }

    private func applyHover(row: Int) {
        let target = items.indices.contains(row) ? row : nil
        guard target != hoveredRow else { return }
        hoveredRow = target
        for visible in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: 0, row: visible, makeIfNecessary: false) as? QueueCell
            else { continue }
            cell.isHovered = (visible == target)
        }
    }

    func apply(items newItems: [QueueItem]) {
        let changed = items.map(\.id) != newItems.map(\.id)
        items = newItems
        if changed {
            tableView.reloadData()
            refreshEmphasis()
        }
        refreshEmptyState()
    }

    private func refreshEmptyState() {
        guard isViewLoaded else { return }
        guard let state = emptyState, items.isEmpty else {
            emptyStack.isHidden = true
            return
        }
        emptySymbol.image = state.symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        }
        emptySymbol.isHidden = emptySymbol.image == nil
        emptyTitle.stringValue = state.title ?? ""
        emptyTitle.isHidden = state.title == nil
        emptyMessage.stringValue = state.message ?? ""
        emptyMessage.isHidden = state.message == nil
        emptyStack.isHidden = false
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

    /// Right-clicking inside the selection acts on all of it; outside one acts on just
    /// that row, matching the tables and the album grid.
    private func contextRows() -> IndexSet {
        let clicked = tableView.clickedRow
        guard items.indices.contains(clicked) else { return [] }
        if tableView.selectedRowIndexes.contains(clicked) { return tableView.selectedRowIndexes }
        return IndexSet(integer: clicked)
    }

    @objc private func menuPlay() {
        guard let first = contextRows().first else { return }
        actions.play(first)
    }

    @objc private func menuRemove() {
        let rows = contextRows()
        guard !rows.isEmpty else { return }
        actions.remove(rows)
    }

    @objc private func menuPlayNext() {
        let rows = contextRows()
        guard !rows.isEmpty else { return }
        actions.playNext(rows, tracks(at: rows))
    }

    @objc private func menuPlayLast() {
        let rows = contextRows()
        guard !rows.isEmpty else { return }
        actions.playLast(rows, tracks(at: rows))
    }

    @objc private func menuGoToAlbum() {
        guard let track = tracks(at: contextRows()).first else { return }
        actions.goToAlbum(track)
    }

    @objc private func menuGoToArtist() {
        guard let track = tracks(at: contextRows()).first else { return }
        actions.goToArtist(track)
    }

    private func tracks(at rows: IndexSet) -> [Track] {
        rows.compactMap { items.indices.contains($0) ? items[$0].track : nil }
    }

    @objc private func menuAddToPlaylist() {
        let rows = contextRows()
        guard !rows.isEmpty else { return }
        actions.addToPlaylist(rows.compactMap { items.indices.contains($0) ? items[$0].track.id : nil })
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
        guard allowsEditing else { return nil }
        guard items.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .onduQueueRows)
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
        if types.contains(.onduQueueRows) { return .move }
        if types.contains(.onduTracks)
            || types.contains(.onduAlbums)
            || types.contains(.onduArtists)
            || types.contains(.onduSidebarPlaylist)
        {
            return .copy
        }
        return []
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let pasteboardItems = info.draggingPasteboard.pasteboardItems ?? []

        let movedRows = pasteboardItems.compactMap { $0.string(forType: .onduQueueRows).flatMap(Int.init) }
        if !movedRows.isEmpty {
            actions.move(IndexSet(movedRows), row)
            return true
        }

        // Before tracks and albums: a playlist drag carries only this type, and the
        // sidebar's own reorder never reaches here — that drop lands on the outline.
        let playlistIds = info.onduIds(forType: .onduSidebarPlaylist)
        if !playlistIds.isEmpty {
            actions.insertPlaylists(playlistIds, row)
            return true
        }

        let albumIds = info.onduIds(forType: .onduAlbums)
        if !albumIds.isEmpty {
            actions.insertAlbums(albumIds, row)
            return true
        }

        let artistIds = info.onduIds(forType: .onduArtists)
        if !artistIds.isEmpty {
            actions.insertArtists(artistIds, row)
            return true
        }

        let trackIds = info.onduIds(forType: .onduTracks)
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

extension QueueTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard items.indices.contains(tableView.clickedRow) else { return }
        addItem(to: menu, title: "Play", action: #selector(menuPlay))
        addItem(to: menu, title: "Play Next", action: #selector(menuPlayNext))
        addItem(to: menu, title: "Play Last", action: #selector(menuPlayLast))
        menu.addItem(.separator())
        addItem(to: menu, title: "Add to Playlist…", action: #selector(menuAddToPlaylist))
        menu.addItem(.separator())
        addItem(to: menu, title: "Go to Album", action: #selector(menuGoToAlbum))
        addItem(to: menu, title: "Go to Artist", action: #selector(menuGoToArtist))
        guard allowsEditing else { return }
        menu.addItem(.separator())
        addItem(to: menu, title: "Remove from Queue", action: #selector(menuRemove))
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
}

extension QueueTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let cell =
            tableView.makeView(withIdentifier: QueueCell.identifier, owner: self) as? QueueCell
            ?? QueueCell()
        cell.showsDuration = showsDuration
        cell.showsRemoveButton = allowsEditing
        cell.metrics = metrics
        // From the row's *current* state, not only from later changes: a recycled cell
        // otherwise keeps the emphasis of whatever row it last showed.
        cell.backgroundStyle = tableView.selectedRowIndexes.contains(row) ? .emphasized : .normal
        cell.isHovered = (row == hoveredRow)
        cell.onRemove = { [weak self] in self?.remove(row: row) }
        cell.configure(item: items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = AccentSelectionRowView()
        view.selectionColor = accentNSColor
        view.customSelectionLeftInset = 8
        view.customSelectionRightInset = 8
        // White text stays, and the pill darkens instead — Music.app's Up Next does the
        // same. Without the flag the row view resets the cell to unemphasized on every
        // selection and key change, which is what kept defeating this.
        view.keepsEmphasisWhenInactive = true
        view.unemphasizedSelectionColor =
            NSColor.unemphasizedSelectedContentBackgroundColor
            .blended(withFraction: 0.35, of: .black) ?? .unemphasizedSelectedContentBackgroundColor
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
        refreshEmphasis()
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
        durationTrailing = duration.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -metrics.horizontalInset)
        removeTrailing = removeButton.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -(metrics.horizontalInset - 2))

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
        isHovered = false
        backgroundStyle = .normal
    }

    @objc private func handleRemove() { onRemove?() }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        let emphasized = backgroundStyle == .emphasized
        title.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        let secondary: NSColor =
            emphasized
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.85)
            : .secondaryLabelColor
        artist.textColor = secondary
        duration.textColor = secondary
        removeButton.contentTintColor = secondary
    }

    /// Driven by the controller, not a tracking area of this cell's own: rows move under
    /// a stationary cursor while scrolling and never get mouseExited, which left the
    /// hover stuck until the pointer moved again.
    ///
    /// The duration gives way to the button rather than sitting beside it, so the row
    /// doesn't reflow on hover.
    var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            applyHoverAffordance()
        }
    }

    /// Nothing to remove in History, so the duration stays put on hover.
    var showsRemoveButton: Bool = true {
        didSet {
            guard showsRemoveButton != oldValue else { return }
            applyHoverAffordance()
        }
    }

    private func applyHoverAffordance() {
        let showsRemove = isHovered && showsRemoveButton
        removeButton.isHidden = !showsRemove
        duration.isHidden = showsRemove || !showsDuration
    }
}

/// How a queue row is inset and how big its artwork is. The window's panel and the mini
/// player's differ in both, and a row that ignores that either misaligns with its header
/// or crowds its own artwork.
struct QueueCellMetrics: Equatable {
    var horizontalInset: CGFloat
    var artworkSize: CGFloat
}

/// Lets every click and drag through to the table beneath the empty-state text.
private final class NonInteractiveContainer: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
#endif
