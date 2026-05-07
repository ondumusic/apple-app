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
    /// Whether to render the Artist column. Set false on AlbumDetailView when the album
    /// has a single artist (the column would be redundant).
    var showArtist: Bool = true
    /// Whether to render the Album column. Set true on Songs/Search views, false in
    /// album detail (already obvious).
    var showAlbum: Bool = false

    func makeNSViewController(context: Context) -> TracksTableViewController {
        let vc = TracksTableViewController()
        vc.onSelectionChange = { ids in selection = ids }
        vc.onPlay = onPlay
        return vc
    }

    func updateNSViewController(_ vc: TracksTableViewController, context: Context) {
        vc.update(
            tracks: tracks,
            externalSelection: selection,
            showArtist: showArtist,
            showAlbum: showAlbum
        )
    }
}

// MARK: - View Controller

final class TracksTableViewController: NSViewController {
    var onSelectionChange: ((Set<UUID>) -> Void)?
    var onPlay: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private(set) var tracks: [Track] = []

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

        configureColumn(numberColumn,   title: "#",        width: 36,  alignment: .right,  resizable: false)
        configureColumn(titleColumn,    title: "Title",    width: 280, alignment: .left,   resizable: true)
        configureColumn(artistColumn,   title: "Artist",   width: 180, alignment: .left,   resizable: true)
        configureColumn(albumColumn,    title: "Album",    width: 180, alignment: .left,   resizable: true)
        configureColumn(durationColumn, title: "Duration", width: 70,  alignment: .right,  resizable: false)

        for column in [numberColumn, titleColumn, artistColumn, albumColumn, durationColumn] {
            tableView.addTableColumn(column)
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

    func update(tracks newTracks: [Track], externalSelection: Set<UUID>, showArtist: Bool, showAlbum: Bool) {
        artistColumn.isHidden = !showArtist
        albumColumn.isHidden = !showAlbum

        let changed = !tracksMatch(self.tracks, newTracks)
        self.tracks = newTracks
        if changed {
            tableView.reloadData()
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
        onPlay?(row)
    }
}

// MARK: - Data Source

extension TracksTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tracks.count
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
