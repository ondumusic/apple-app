#if os(macOS)
import AppKit
import Nuke
import SwiftUI

/// Downloaded albums as a real table — columns, multi-select, type-to-select and the
/// Delete key, matching every other list in the app. The shared iOS DownloadsView is a
/// SwiftUI List of 63pt two-line rows, which reads as a phone screen in a Mac window.
struct DownloadsTable: NSViewControllerRepresentable {
    let entries: [DownloadedAlbumEntry]
    @Binding var selection: Set<UUID>
    let accent: Color
    /// Double-click, and the context menu's "Go to Album".
    let onOpen: (Album) -> Void
    let onPlay: (Album) -> Void
    let onRemove: ([Album]) -> Void

    func makeNSViewController(context: Context) -> DownloadsTableViewController {
        let vc = DownloadsTableViewController()
        apply(to: vc)
        return vc
    }

    func updateNSViewController(_ vc: DownloadsTableViewController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: DownloadsTableViewController) {
        vc.accentNSColor = NSColor(accent)
        vc.onOpen = onOpen
        vc.onPlay = onPlay
        vc.onRemove = onRemove
        vc.onSelectionChange = { selection = $0 }
        vc.apply(entries: entries, selection: selection)
    }
}

final class DownloadsTableViewController: NSViewController {
    fileprivate var entries: [DownloadedAlbumEntry] = []
    var onOpen: ((Album) -> Void)?
    var onPlay: ((Album) -> Void)?
    var onRemove: (([Album]) -> Void)?
    var onSelectionChange: ((Set<UUID>) -> Void)?

    var accentNSColor: NSColor = .controlAccentColor {
        didSet {
            guard accentNSColor != oldValue, isViewLoaded else { return }
            tableView.enumerateAvailableRowViews { rowView, _ in
                (rowView as? AccentSelectionRowView)?.selectionColor = accentNSColor
                rowView.needsDisplay = true
            }
        }
    }

    private let scrollView = NSScrollView()
    private let tableView = DeleteAwareTableView()
    private var isApplyingExternalSelection = false

    private let albumColumn = NSTableColumn(identifier: .init("album"))
    private let artistColumn = NSTableColumn(identifier: .init("artist"))
    private let songsColumn = NSTableColumn(identifier: .init("songs"))
    private let sizeColumn = NSTableColumn(identifier: .init("size"))

    override func loadView() {
        configure(albumColumn, title: "Album", width: 320, alignment: .left, resizable: true)
        configure(artistColumn, title: "Artist", width: 220, alignment: .left, resizable: false)
        configure(songsColumn, title: "Songs", width: 70, alignment: .right, resizable: false)
        configure(sizeColumn, title: "Size", width: 90, alignment: .right, resizable: false)
        for column in [albumColumn, artistColumn, songsColumn, sizeColumn] {
            tableView.addTableColumn(column)
        }

        tableView.style = .inset
        // Tall enough for the 32pt artwork the rows carry.
        tableView.rowHeight = 44
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        // .none so AccentSelectionRowView's pill paints instead of the system accent.
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.onDelete = { [weak self] in self?.removeSelected() }

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        view = scrollView
    }

    private func configure(_ column: NSTableColumn, title: String, width: CGFloat,
                           alignment: NSTextAlignment, resizable: Bool) {
        column.title = title
        column.width = width
        column.minWidth = resizable ? 120 : width
        column.maxWidth = resizable ? 4000 : width
        column.headerCell.alignment = alignment
        // Album absorbs the spare width; without an autoresizing column everything past
        // Size is dead space and the stripes run out under nothing.
        column.resizingMask = resizable ? [.autoresizingMask, .userResizingMask] : []
    }

    func apply(entries newEntries: [DownloadedAlbumEntry], selection: Set<UUID>) {
        let changed = entries != newEntries
        entries = newEntries
        if changed { tableView.reloadData() }

        let targetRows = IndexSet(entries.indices.filter { selection.contains(entries[$0].id) })
        guard targetRows != tableView.selectedRowIndexes else { return }
        isApplyingExternalSelection = true
        tableView.selectRowIndexes(targetRows, byExtendingSelection: false)
        isApplyingExternalSelection = false
    }

    /// Rows the menu or the Delete key should act on: the selection, or the row that was
    /// right-clicked when it sits outside the selection.
    private func targetEntries() -> [DownloadedAlbumEntry] {
        let clicked = tableView.clickedRow
        if entries.indices.contains(clicked), !tableView.selectedRowIndexes.contains(clicked) {
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
            return [entries[clicked]]
        }
        return tableView.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
    }

    private func removeSelected() {
        let albums = targetEntries().map(\.album)
        guard !albums.isEmpty else { return }
        onRemove?(albums)
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard entries.indices.contains(row) else { return }
        onOpen?(entries[row].album)
    }

    @objc private func menuPlay() {
        guard let album = targetEntries().first?.album else { return }
        onPlay?(album)
    }

    @objc private func menuOpen() {
        guard let album = targetEntries().first?.album else { return }
        onOpen?(album)
    }

    @objc private func menuRemove() { removeSelected() }
}

extension DownloadsTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
}

extension DownloadsTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = AccentSelectionRowView()
        view.selectionColor = accentNSColor
        // Matches the margin `style = .inset` gives the alternating rows.
        view.customSelectionLeftInset = 10
        view.customSelectionRightInset = 10
        view.suppressDivider = true
        view.drawsRowBackground = true
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let column = tableColumn else { return nil }
        let entry = entries[row]
        let emphasized = tableView.selectedRowIndexes.contains(row)

        if column === albumColumn {
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? DownloadAlbumCell
                ?? DownloadAlbumCell(identifier: column.identifier)
            cell.configure(album: entry.album)
            cell.backgroundStyle = emphasized ? .emphasized : .normal
            return cell
        }

        let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? DownloadTextCell
            ?? DownloadTextCell(identifier: column.identifier,
                                alignment: column === albumColumn ? .left : (column === artistColumn ? .left : .right))
        switch column {
        case artistColumn: cell.label.stringValue = entry.album.artistName ?? ""
        case songsColumn: cell.label.stringValue = "\(entry.trackCount)"
        default: cell.label.stringValue = ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
        }
        cell.isSecondary = column !== albumColumn
        cell.backgroundStyle = emphasized ? .emphasized : .normal
        return cell
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        entries.indices.contains(row) ? entries[row].album.name : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // selectionHighlightStyle = .none means NSTableView won't redraw rows itself.
        tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
        guard !isApplyingExternalSelection else { return }
        let ids = tableView.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].id : nil }
        onSelectionChange?(Set(ids))
    }
}

extension DownloadsTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard !targetEntries().isEmpty else { return }
        add(to: menu, title: "Play", action: #selector(menuPlay))
        add(to: menu, title: "Go to Album", action: #selector(menuOpen))
        menu.addItem(.separator())
        add(to: menu, title: "Remove Download", action: #selector(menuRemove))
    }

    private func add(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
}

/// NSTableView that reports Backspace / forward Delete so rows can be removed from the
/// keyboard, the way a Finder-style list behaves.
private final class DeleteAwareTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let deleteKeys: Set<UInt16> = [51, 117]
        if deleteKeys.contains(event.keyCode), selectedRow >= 0 {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

/// Artwork plus album title. Nuke loads straight into an NSImageView here rather than
/// hosting a SwiftUI ArtworkView per row — one hosting view per row is a lot of machinery
/// for a 32pt thumbnail.
private final class DownloadAlbumCell: NSTableCellView {
    private let artwork = NSImageView()
    let label = NSTextField(labelWithString: "")
    private var loadingURL: URL?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 4
        artwork.layer?.masksToBounds = true
        artwork.layer?.borderWidth = 0.5
        artwork.layer?.borderColor = NSColor.separatorColor.cgColor
        addSubview(artwork)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)

        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 32),
            artwork.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func configure(album: Album) {
        label.stringValue = album.name
        applyEmphasis()
        guard loadingURL != album.artworkUrl else { return }
        loadingURL = album.artworkUrl
        artwork.image = nil
        guard let url = album.artworkUrl else { return }
        ImagePipeline.shared.loadImage(with: url) { [weak self] result in
            guard let self, self.loadingURL == url else { return }  // cell was recycled
            if case .success(let response) = result { self.artwork.image = response.image }
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        label.textColor = backgroundStyle == .emphasized ? .white : .labelColor
    }
}

private final class DownloadTextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    var isSecondary = false { didSet { applyEmphasis() } }

    init(identifier: NSUserInterfaceItemIdentifier, alignment: NSTextAlignment) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        if backgroundStyle == .emphasized {
            label.textColor = .white
        } else {
            label.textColor = isSecondary ? .secondaryLabelColor : .labelColor
        }
    }
}
#endif
