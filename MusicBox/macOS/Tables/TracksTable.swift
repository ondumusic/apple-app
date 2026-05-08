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

    func makeNSViewController(context: Context) -> TracksTableViewController {
        let vc = TracksTableViewController()
        vc.onSelectionChange = { ids in selection = ids }
        vc.onPlay = onPlay
        vc.actions = actions
        return vc
    }

    func updateNSViewController(_ vc: TracksTableViewController, context: Context) {
        vc.actions = actions
        vc.update(
            tracks: tracks,
            externalSelection: selection,
            showArtist: showArtist,
            showAlbum: showAlbum,
            currentlyPlayingTrackId: currentlyPlayingTrackId,
            isPlaying: isPlaying
        )
    }
}

// MARK: - View Controller

final class TracksTableViewController: NSViewController {
    var onSelectionChange: ((Set<UUID>) -> Void)?
    var onPlay: ((Int) -> Void)?
    var actions: TrackActions = TrackActions()

    private let scrollView = NSScrollView()
    private let tableView = KeyAwareTableView()
    private(set) var tracks: [Track] = []
    private var currentlyPlayingTrackId: UUID?
    private var isPlaying: Bool = false

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

        // Drag source: lets tracks be dropped onto sidebar playlist rows.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

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

    func update(
        tracks newTracks: [Track],
        externalSelection: Set<UUID>,
        showArtist: Bool,
        showAlbum: Bool,
        currentlyPlayingTrackId newCurrent: UUID?,
        isPlaying newIsPlaying: Bool
    ) {
        artistColumn.isHidden = !showArtist
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

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = numpad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            onEnter?()
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
}

// MARK: - Delegate

extension TracksTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < tracks.count else { return nil }
        let track = tracks[row]

        let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? TextCell
            ?? TextCell(identifier: column.identifier)

        switch column.identifier.rawValue {
        case "number":
            cell.label.stringValue = track.number.map(String.init) ?? "–"
            cell.label.alignment = .right
            cell.label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            cell.label.textColor = .secondaryLabelColor
        case "title":
            cell.label.stringValue = track.name
            cell.label.alignment = .left
            cell.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.label.textColor = .labelColor
        case "artist":
            cell.label.stringValue = track.artist.name
            cell.label.alignment = .left
            cell.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.label.textColor = .secondaryLabelColor
        case "album":
            cell.label.stringValue = track.album?.name ?? ""
            cell.label.alignment = .left
            cell.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.label.textColor = .secondaryLabelColor
        case "duration":
            cell.label.stringValue = track.formattedDuration
            cell.label.alignment = .right
            cell.label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            cell.label.textColor = .secondaryLabelColor
        default:
            cell.label.stringValue = ""
        }
        return cell
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
}

// MARK: - Cell

private final class TextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")

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
}
#endif
