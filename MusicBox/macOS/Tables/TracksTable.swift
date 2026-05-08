#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI bridge for the AppKit tracks table. Used inside album detail, playlist detail,
/// search results, and the songs category view. Native multi-select (cmd/shift-click),
/// double-click to play, type-ahead — all the things SwiftUI's List can't quite get right
/// for data-dense music tables.
struct TracksTable: NSViewControllerRepresentable {
    let tracks: [Track]
    @Binding var selection: Set<UUID>
    let onPlay: (Int) -> Void
    let actions: TrackActions
    /// Whether to render the Artist column. Set false on AlbumDetailView when the album
    /// has a single artist (the column would be redundant).
    var showArtist: Bool = true
    /// Whether to render the Album column. Set true on Songs/Search views, false in
    /// album detail (already obvious).
    var showAlbum: Bool = false
    /// Currently-playing track id; the matching row's # column shows a speaker glyph
    /// instead of the track number.
    var currentlyPlayingTrackId: UUID?
    var isPlaying: Bool = false
    /// When true, the # column shows the row's 1-based position (1, 2, 3…) instead of
    /// the track's intrinsic number. Useful for PlaylistDetailMac where ordering differs
    /// from album-track-number ordering.
    var usesPlaylistPosition: Bool = false
    /// Drop target for reorder-within-table drags. Receives the dragged row indices and
    /// the proposed insertion row index. Nil disables internal reorder.
    var onReorder: ((IndexSet, Int) -> Void)?
    /// Backspace / Delete handler. Receives the currently-selected row indices. Nil
    /// disables keyboard delete.
    var onDelete: ((IndexSet) -> Void)?
    /// Hide the column header row. Useful when embedding the table inside a section that
    /// already has its own header (e.g. ArtistDetailMac's per-album sections).
    var hidesColumnHeaders: Bool = false
    /// Override the default row height. Nil = NSTableView's default for the inset style.
    var rowHeight: CGFloat?
    /// "Embedded" styling: no scrollbar gutter, no alternating row backgrounds, rounded
    /// selection that merges across adjacent selected rows. Use when the table sits
    /// inline inside a parent ScrollView.
    var embeddedStyle: Bool = false

    func makeNSViewController(context: Context) -> TracksTableViewController {
        let vc = TracksTableViewController()
        vc.onSelectionChange = { ids in selection = ids }
        vc.onPlay = onPlay
        vc.actions = actions
        vc.onReorder = onReorder
        vc.onDelete = onDelete
        vc.applyEmbeddedStyle(embeddedStyle)
        vc.applyHeaderVisibility(hidden: hidesColumnHeaders)
        vc.applyRowHeight(rowHeight)
        return vc
    }

    func updateNSViewController(_ vc: TracksTableViewController, context: Context) {
        vc.actions = actions
        vc.onReorder = onReorder
        vc.onDelete = onDelete
        vc.applyEmbeddedStyle(embeddedStyle)
        vc.applyHeaderVisibility(hidden: hidesColumnHeaders)
        vc.applyRowHeight(rowHeight)
        vc.update(
            tracks: tracks,
            externalSelection: selection,
            showArtist: showArtist,
            showAlbum: showAlbum,
            currentlyPlayingTrackId: currentlyPlayingTrackId,
            isPlaying: isPlaying,
            usesPlaylistPosition: usesPlaylistPosition
        )
    }
}

// MARK: - View Controller

final class TracksTableViewController: NSViewController {
    var onSelectionChange: ((Set<UUID>) -> Void)?
    var onPlay: ((Int) -> Void)?
    var actions: TrackActions = TrackActions()
    var onReorder: ((IndexSet, Int) -> Void)?
    var onDelete: ((IndexSet) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = KeyAwareTableView()
    private(set) var tracks: [Track] = []
    private var currentlyPlayingTrackId: UUID?
    private var isPlaying: Bool = false
    private var usesPlaylistPosition: Bool = false
    /// Tracks whether the host asked for artist info in embedded mode. The cell uses
    /// this to decide whether to render an artist subline under the title.
    private var embeddedShowsArtist: Bool = false

    private let numberColumn = NSTableColumn(identifier: .init("number"))
    private let titleColumn  = NSTableColumn(identifier: .init("title"))
    private let artistColumn = NSTableColumn(identifier: .init("artist"))
    private let albumColumn  = NSTableColumn(identifier: .init("album"))
    private let durationColumn = NSTableColumn(identifier: .init("duration"))

    private var suppressSelectionCallback = false

    override func loadView() {
        view = NSView()

        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .default
        tableView.style = .inset
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onEnter = { [weak self] in self?.handleEnter() }

        configureColumn(numberColumn,   title: "#",        width: 36,  alignment: .right,  resizable: false)
        configureColumn(titleColumn,    title: "Title",    width: 280, alignment: .left,   resizable: true)
        configureColumn(artistColumn,   title: "Artist",   width: 180, alignment: .left,   resizable: true)
        configureColumn(albumColumn,    title: "Album",    width: 180, alignment: .left,   resizable: true)
        configureColumn(durationColumn, title: "Duration", width: 70,  alignment: .right,  resizable: false)

        for column in [numberColumn, titleColumn, artistColumn, albumColumn, durationColumn] {
            tableView.addTableColumn(column)
        }

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        // Drag source: tracks can be dropped onto sidebar playlist rows (.copy externally)
        // or reordered within this same table (.move locally).
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        // Self-drop target so we can intercept reorder drags.
        tableView.registerForDraggedTypes([.musicBoxTracks])

        tableView.onDelete = { [weak self] in
            guard let self, let onDelete = self.onDelete else { return }
            let rows = self.tableView.selectedRowIndexes
            guard !rows.isEmpty else { return }
            onDelete(rows)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureColumn(_ column: NSTableColumn, title: String, width: CGFloat, alignment: NSTextAlignment, resizable: Bool) {
        column.title = title
        column.width = width
        column.minWidth = max(24, width / 2)
        column.maxWidth = resizable ? 1000 : width
        column.resizingMask = resizable ? [.userResizingMask, .autoresizingMask] : []
        column.headerCell.alignment = alignment
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard isEmbedded else { return }
        // .sourceList highlight inserts NSVisualEffectViews into the row hierarchy for
        // the rounded selection backdrop. We want the rounded pill but not the blur —
        // hide the effect views so the parent's solid background shows through.
        suppressEmbeddedVibrancy(in: scrollView)
        // Pin the tableView's width to the scrollView's clipView width. NSScrollView
        // by default sizes the documentView to the sum of column widths, which makes
        // the table overflow when the parent is narrower than that. Forcing the width
        // lets columnAutoresizingStyle redistribute across the resizable columns.
        let target = scrollView.contentView.bounds.width
        guard target > 0 else { return }
        // NSTableView with .sourceList selection + .fullWidth style insets the column
        // area symmetrically: ~16pt on the leading side, and the same again on the
        // trailing side reserved for the rounded selection pill. Cells must fit inside
        // [inset, frame.width - inset] or they get clipped when a row is selected.
        // We measure the left inset from the first cell's frame and double it.
        let detectedInset: CGFloat = tableView.numberOfRows > 0
            ? tableView.frameOfCell(atColumn: 0, row: 0).minX
            : 16
        let titleWidth = max(120, target - 36 - 70 - 2 * detectedInset)
        if abs(titleColumn.width - titleWidth) > 0.5 {
            titleColumn.width = titleWidth
        }
        if abs(tableView.frame.width - target) > 0.5 {
            tableView.setFrameSize(NSSize(width: target, height: tableView.frame.height))
        }
        #if DEBUG
        let columnDescriptions = tableView.tableColumns.map { col in
            "\(col.identifier.rawValue)=\(col.width)(min=\(col.minWidth),max=\(col.maxWidth),hidden=\(col.isHidden))"
        }.joined(separator: " ")
        let sum = tableView.tableColumns.reduce(0) { $0 + $1.width }
        var cellFrames: [String] = []
        if tableView.numberOfRows > 0 {
            for col in 0..<tableView.numberOfColumns {
                let f = tableView.frameOfCell(atColumn: col, row: 0)
                cellFrames.append("col\(col)=\(Int(f.minX))..\(Int(f.maxX))")
            }
        }
        var rowFrame = "n/a"
        if let rv = tableView.rowView(atRow: 0, makeIfNecessary: false) {
            rowFrame = "\(rv.frame)"
        }
        print("[TT] target=\(target) titleWidth=\(titleWidth) sum=\(sum) tableFrame.w=\(tableView.frame.width) docVisible=\(scrollView.documentVisibleRect.width) intercell=\(tableView.intercellSpacing.width) style=\(tableView.style.rawValue) cellFrames=[\(cellFrames.joined(separator: " "))] row0Frame=\(rowFrame) cols=[\(columnDescriptions)]")
        #endif
    }

    private func suppressEmbeddedVibrancy(in view: NSView) {
        for sub in view.subviews {
            if let ve = sub as? NSVisualEffectView, ve.alphaValue != 0 {
                ve.alphaValue = 0
            }
            suppressEmbeddedVibrancy(in: sub)
        }
    }

    func applyHeaderVisibility(hidden: Bool) {
        _ = view  // force loadView so we override its defaults, not the other way around
        if hidden {
            tableView.headerView = nil
        }
    }

    func applyRowHeight(_ rowHeight: CGFloat?) {
        _ = view
        if let rowHeight {
            // .default rowSizeStyle ignores manual rowHeight — flip to .custom so the
            // override actually takes effect.
            if tableView.rowSizeStyle != .custom { tableView.rowSizeStyle = .custom }
            if abs(tableView.rowHeight - rowHeight) > 0.5 {
                tableView.rowHeight = rowHeight
            }
        } else if tableView.rowSizeStyle != .default {
            tableView.rowSizeStyle = .default
        }
    }

    private(set) var isEmbedded: Bool = false

    func applyEmbeddedStyle(_ embedded: Bool) {
        // makeNSViewController calls these before SwiftUI requests `view`, which is
        // when loadView runs and sets the standalone defaults. Force the load now so
        // our embedded overrides win.
        _ = view
        guard embedded != isEmbedded else { return }
        isEmbedded = embedded
        if embedded {
            // Strip standalone-table chrome — let the parent ScrollView own the scrolling.
            tableView.usesAlternatingRowBackgroundColors = false
            // .fullWidth (rather than .plain) — .plain still paints a grey container
            // behind the rows; .fullWidth lets the parent's background show through.
            tableView.style = .fullWidth
            tableView.gridStyleMask = []
            tableView.intercellSpacing = .zero
            tableView.backgroundColor = .clear
            // .sourceList gives the rounded merged-pill selection we want, but it
            // implicitly inserts an NSVisualEffectView backdrop (the see-through blur).
            // We zero out those effect views in viewDidLayout — see suppressVibrancy().
            tableView.selectionHighlightStyle = .sourceList
            // Fixed widths: number (36) and duration (70) are fully locked. Title is
            // sized manually in viewDidLayout. Remove (not just hide) the artist/album
            // columns — even with isHidden = true and width = 0 they still contribute
            // to the documentView width and overflow the clipView.
            numberColumn.minWidth = 36; numberColumn.maxWidth = 36; numberColumn.width = 36
            durationColumn.minWidth = 70; durationColumn.maxWidth = 70; durationColumn.width = 70
            if tableView.tableColumns.contains(artistColumn) {
                tableView.removeTableColumn(artistColumn)
            }
            if tableView.tableColumns.contains(albumColumn) {
                tableView.removeTableColumn(albumColumn)
            }
            tableView.columnAutoresizingStyle = .noColumnAutoresizing
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            scrollView.borderType = .noBorder
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = .clear
        } else {
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.style = .inset
            tableView.intercellSpacing = NSSize(width: 3, height: 2)
            tableView.backgroundColor = .controlBackgroundColor
            tableView.selectionHighlightStyle = .regular
            scrollView.drawsBackground = true
            scrollView.hasVerticalScroller = true
            scrollView.verticalScrollElasticity = .automatic
        }       
        tableView.reloadData()
    }

    func update(
        tracks newTracks: [Track],
        externalSelection: Set<UUID>,
        showArtist: Bool,
        showAlbum: Bool,
        currentlyPlayingTrackId newCurrent: UUID?,
        isPlaying newIsPlaying: Bool,
        usesPlaylistPosition newUsesPlaylistPosition: Bool
    ) {
        self.usesPlaylistPosition = newUsesPlaylistPosition
        self.embeddedShowsArtist = showArtist
        // Artist column is always hidden in embedded mode — the title cell stacks the
        // artist beneath the title when needed.
        artistColumn.isHidden = isEmbedded || !showArtist
        albumColumn.isHidden = !showAlbum

        let changed = !tracksMatch(self.tracks, newTracks)
        let previousCurrent = self.currentlyPlayingTrackId
        let previousPlaying = self.isPlaying
        self.tracks = newTracks
        self.currentlyPlayingTrackId = newCurrent
        self.isPlaying = newIsPlaying

        if changed {
            tableView.reloadData()
        } else if previousCurrent != newCurrent || previousPlaying != newIsPlaying {
            // Only the play indicator needs refreshing — reload just the affected rows
            // so we don't kill in-flight clicks.
            var rows = IndexSet()
            if let prev = previousCurrent, let row = tracks.firstIndex(where: { $0.id == prev }) {
                rows.insert(row)
            }
            if let cur = newCurrent, let row = tracks.firstIndex(where: { $0.id == cur }) {
                rows.insert(row)
            }
            if !rows.isEmpty {
                tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
            }
        }
        applyExternalSelection(externalSelection)
    }

    private func tracksMatch(_ a: [Track], _ b: [Track]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            if lhs.id != rhs.id { return false }
        }
        // Intentionally ignores isDownloaded — a flip there triggers SwiftUI re-renders
        // mid-click which would call reloadData() and cancel an in-flight double-click.
        // The downloaded indicator can be refreshed per-row when we add it.
        return true
    }

    private func applyExternalSelection(_ ids: Set<UUID>) {
        if ids.isEmpty {
            if !tableView.selectedRowIndexes.isEmpty {
                suppressSelectionCallback = true
                tableView.deselectAll(nil)
                suppressSelectionCallback = false
            }
            return
        }
        let indices = IndexSet(tracks.enumerated().compactMap { ids.contains($1.id) ? $0 : nil })
        if indices == tableView.selectedRowIndexes { return }
        suppressSelectionCallback = true
        tableView.selectRowIndexes(indices, byExtendingSelection: false)
        suppressSelectionCallback = false
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < tracks.count else { return }
        let track = tracks[row]

        // iTunes-style: double-click on the Artist column navigates to the artist;
        // Album column navigates to the album. Anywhere else plays the track.
        let col = tableView.clickedColumn
        if col >= 0, col < tableView.tableColumns.count {
            switch tableView.tableColumns[col].identifier.rawValue {
            case "artist":
                actions.goToArtist(track)
                return
            case "album":
                actions.goToAlbum(track)
                return
            default: break
            }
        }
        onPlay?(row)
    }

    private func handleEnter() {
        // Enter on a single selection plays that row; on multi-selection, plays the
        // earliest selected row (same semantic as iTunes / Apple Music).
        guard let firstSelected = tableView.selectedRowIndexes.min(),
              tracks.indices.contains(firstSelected) else { return }
        onPlay?(firstSelected)
    }
}

// MARK: - Key-aware table

private final class KeyAwareTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = numpad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnter?()
            return
        }
        // 51 = Delete (Backspace), 117 = forward Delete.
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Data Source

extension TracksTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tracks.count
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tracks.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(tracks[row].id.uuidString, forType: .musicBoxTracks)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Only handle internal reorder drags. Drops onto specific rows aren't supported here.
        guard onReorder != nil,
              dropOperation == .above,
              info.draggingSource as? NSTableView === self.tableView
        else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation dropOperation: NSTableView.DropOperation) -> Bool {
        guard let onReorder,
              dropOperation == .above,
              info.draggingSource as? NSTableView === self.tableView
        else { return false }
        let rows = self.tableView.selectedRowIndexes
        guard !rows.isEmpty else { return false }
        onReorder(rows, row)
        return true
    }
}

// MARK: - Delegate

extension TracksTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // In embedded mode, NSTableRowView's default drawBackground paints a backdrop
        // even when tableView.backgroundColor is .clear — that's the residual grey we
        // were seeing. Custom row view no-ops the draw so the parent shows through and
        // also paints the inter-row hairline divider.
        guard isEmbedded else { return nil }
        let view = EmbeddedRowView()
        view.isLastRow = (row == tracks.count - 1)
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < tracks.count else { return nil }
        let track = tracks[row]
        let isCurrent = currentlyPlayingTrackId == track.id

        switch column.identifier.rawValue {
        case "number":
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NumberOrSpeakerCell
                ?? NumberOrSpeakerCell(identifier: column.identifier)
            if isCurrent {
                cell.showSpeaker(playing: isPlaying)
            } else {
                let display: String
                if usesPlaylistPosition {
                    display = String(row + 1)
                } else {
                    display = track.number.map(String.init) ?? "–"
                }
                cell.showNumber(display)
            }
            return cell
        case "title":
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? TitleCell
                ?? TitleCell(identifier: column.identifier)
            // In embedded mode we hide the Artist column and stack the artist beneath
            // the title when the host wanted artist info — consistent with iTunes /
            // Apple Music layout for inline album sections.
            let inlineArtist = isEmbedded && embeddedShowsArtist
            cell.configure(track: track, isCurrent: isCurrent, showArtistInline: inlineArtist)
            return cell
        case "artist":
            let cell = textCell(for: column.identifier, in: tableView)
            cell.label.stringValue = track.artist.name
            cell.label.alignment = .left
            cell.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.unselectedColor = .secondaryLabelColor
            return cell
        case "album":
            let cell = textCell(for: column.identifier, in: tableView)
            cell.label.stringValue = track.album?.name ?? ""
            cell.label.alignment = .left
            cell.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.unselectedColor = .secondaryLabelColor
            return cell
        case "duration":
            let cell = textCell(for: column.identifier, in: tableView)
            cell.label.stringValue = track.formattedDuration
            cell.label.alignment = .right
            cell.label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            cell.unselectedColor = .secondaryLabelColor
            return cell
        default:
            return nil
        }
    }

    private func textCell(for identifier: NSUserInterfaceItemIdentifier, in tableView: NSTableView) -> TextCell {
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? TextCell {
            return existing
        }
        return TextCell(identifier: identifier)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if suppressSelectionCallback { return }
        let ids = Set(tableView.selectedRowIndexes.compactMap { idx in
            tracks.indices.contains(idx) ? tracks[idx].id : nil
        })
        onSelectionChange?(ids)
    }
}

// MARK: - Context Menu

extension TracksTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let targetTracks = tracksForContextAction()
        guard !targetTracks.isEmpty else { return }

        let isSingle = targetTracks.count == 1
        let primaryTitle = isSingle ? "Play" : "Play \(targetTracks.count) Songs"
        addItem(to: menu, title: primaryTitle, action: #selector(menuPlay))
        addItem(to: menu, title: "Shuffle", action: #selector(menuShuffle))
        menu.addItem(.separator())
        addItem(to: menu, title: "Play Next", action: #selector(menuPlayNext))
        addItem(to: menu, title: "Add to Queue", action: #selector(menuAddToEnd))
        menu.addItem(.separator())
        addItem(to: menu, title: "Add to Playlist…", action: #selector(menuAddToPlaylist))
        if actions.removeFromPlaylistRows != nil {
            let removeTitle = isSingle ? "Remove from Playlist" : "Remove \(targetTracks.count) from Playlist"
            addItem(to: menu, title: removeTitle, action: #selector(menuRemoveFromPlaylist))
        }
        if isSingle {
            menu.addItem(.separator())
            addItem(to: menu, title: "Go to Album", action: #selector(menuGoToAlbum))
            addItem(to: menu, title: "Go to Artist", action: #selector(menuGoToArtist))
        }
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    /// If the right-clicked row is in the current selection, the action applies to the
    /// whole selection. Otherwise it applies to just the clicked row (and the click also
    /// selects that row to make the intent visible).
    private func tracksForContextAction() -> [Track] {
        let clicked = tableView.clickedRow
        guard clicked >= 0, clicked < tracks.count else { return [] }
        if tableView.selectedRowIndexes.contains(clicked) {
            return tableView.selectedRowIndexes.compactMap { tracks.indices.contains($0) ? tracks[$0] : nil }
        }
        // Clicked an unselected row → just that row, and adopt it as selection so subsequent
        // actions (Play All etc. in the toolbar) target what the user expects.
        suppressSelectionCallback = true
        tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        suppressSelectionCallback = false
        onSelectionChange?(Set([tracks[clicked].id]))
        return [tracks[clicked]]
    }

    @objc private func menuPlay() { actions.play(tracksForContextAction()) }
    @objc private func menuShuffle() {
        // Shuffle is "play these in shuffled order" — caller's play() handles ordering, so
        // we just pass shuffled tracks. Most call sites use playShuffled which re-shuffles.
        actions.play(tracksForContextAction().shuffled())
    }
    @objc private func menuPlayNext() { actions.playNext(tracksForContextAction()) }
    @objc private func menuAddToEnd() { actions.addToEnd(tracksForContextAction()) }
    @objc private func menuAddToPlaylist() { actions.addToPlaylist(tracksForContextAction().map(\.id)) }
    @objc private func menuGoToAlbum() {
        if let track = tracksForContextAction().first { actions.goToAlbum(track) }
    }
    @objc private func menuGoToArtist() {
        if let track = tracksForContextAction().first { actions.goToArtist(track) }
    }
    @objc private func menuRemoveFromPlaylist() {
        guard let removeFromPlaylistRows = actions.removeFromPlaylistRows else { return }
        // Use the same row resolution as other actions: clicked row narrows the selection
        // when not already part of it.
        _ = tracksForContextAction()
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return }
        removeFromPlaylistRows(rows)
    }
}

// MARK: - Row View

/// Embedded-mode row view that draws no backdrop. NSTableView's `backgroundColor = .clear`
/// alone doesn't suppress the row-level backdrop the system paints under each row — this
/// override is what actually makes the parent's color show through.
private final class EmbeddedRowView: NSTableRowView {
    /// Set by the delegate so we can suppress the bottom hairline on the final row
    /// — NSTableRowView itself doesn't know its position in the table.
    var isLastRow: Bool = false

    override func drawBackground(in dirtyRect: NSRect) {
        // Subtle hairline divider at the bottom. Skipped on the last row, on selected
        // rows, and when the row below is selected (so the rounded selection pill never
        // has a line slicing through it). Drawn here because NSTableView with zero
        // intercellSpacing doesn't call drawSeparator.
        guard !isLastRow, !isSelected, !isNextRowSelected else { return }
        let line = NSRect(x: bounds.minX + 8,
                          y: bounds.maxY - 0.5,
                          width: bounds.width - 16,
                          height: 0.5)
        NSColor.separatorColor.setFill()
        line.fill()
    }

    override func drawSeparator(in dirtyRect: NSRect) {}
}

// MARK: - Cell

private final class TextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    /// Color the label uses when the row is not selected. The delegate sets it
    /// per-column (artist/album/duration are all secondary muted).
    var unselectedColor: NSColor = .secondaryLabelColor {
        didSet { applyEmphasis() }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        label.textColor = backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor
            : unselectedColor
    }
}

/// # column cell. Switches between a track number/position and a speaker glyph for
/// the currently-playing row.
private final class NumberOrSpeakerCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        addSubview(label)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        icon.contentTintColor = .controlAccentColor
        icon.isHidden = true
        addSubview(icon)

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func showNumber(_ text: String) {
        label.stringValue = text
        label.isHidden = false
        icon.isHidden = true
    }

    func showSpeaker(playing: Bool) {
        let symbol = playing ? "speaker.wave.2.fill" : "speaker.fill"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.isHidden = false
        label.isHidden = true
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        let emphasized = backgroundStyle == .emphasized
        label.textColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        icon.contentTintColor = emphasized ? .alternateSelectedControlTextColor : .controlAccentColor
    }
}

/// Title column cell: track name + (optional) artist subline + downloaded indicator.
/// In standalone mode the artist lives in its own column so this cell only needs to
/// render the title; in embedded mode the artist column is hidden and we stack the
/// artist beneath the title when relevant. The title supports up to 2 lines either
/// way so long names wrap instead of truncating.
private final class TitleCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let artistLabel = NSTextField(labelWithString: "")
    let downloadedIcon = NSImageView()
    private var isCurrent: Bool = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.cell?.wraps = true
        addSubview(label)
        textField = label

        artistLabel.translatesAutoresizingMaskIntoConstraints = false
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.maximumNumberOfLines = 1
        artistLabel.cell?.usesSingleLineMode = true
        artistLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.isHidden = true
        addSubview(artistLabel)

        downloadedIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadedIcon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloaded")
        downloadedIcon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        downloadedIcon.contentTintColor = .secondaryLabelColor
        downloadedIcon.isHidden = true
        addSubview(downloadedIcon)

        let stack = NSStackView(views: [label, artistLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: downloadedIcon.leadingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            downloadedIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            downloadedIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            downloadedIcon.widthAnchor.constraint(equalToConstant: 14),
            downloadedIcon.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(track: Track, isCurrent: Bool, showArtistInline: Bool) {
        self.isCurrent = isCurrent
        label.stringValue = track.name
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        artistLabel.stringValue = track.artist.name
        artistLabel.isHidden = !showArtistInline
        downloadedIcon.isHidden = !track.isDownloaded
        applyEmphasis()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        let emphasized = backgroundStyle == .emphasized
        if emphasized {
            label.textColor = .alternateSelectedControlTextColor
            artistLabel.textColor = .alternateSelectedControlTextColor
            downloadedIcon.contentTintColor = .alternateSelectedControlTextColor
        } else {
            label.textColor = isCurrent ? .controlAccentColor : .labelColor
            artistLabel.textColor = .secondaryLabelColor
            downloadedIcon.contentTintColor = .secondaryLabelColor
        }
    }
}
#endif
