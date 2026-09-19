#if os(macOS)
import AppKit
import SwiftUI

/// AppKit-backed artist list. A SwiftUI `List` consumes the double-click that means
/// "play" everywhere else on the Mac, and gives no type-to-select; NSTableView provides
/// both natively, and matches how the tracks tables are already built.
struct ArtistsTable: NSViewControllerRepresentable {
    let artists: [Artist]
    @Binding var selection: Artist.ID?
    let actions: ArtistActions
    let accent: Color

    func makeNSViewController(context: Context) -> ArtistsTableViewController {
        let vc = ArtistsTableViewController()
        vc.accentNSColor = NSColor(accent)
        vc.actions = actions
        vc.onSelectionChange = { selection = $0 }
        vc.apply(artists: artists, selection: selection)
        return vc
    }

    func updateNSViewController(_ vc: ArtistsTableViewController, context: Context) {
        vc.accentNSColor = NSColor(accent)
        vc.actions = actions
        vc.onSelectionChange = { selection = $0 }
        vc.apply(artists: artists, selection: selection)
    }
}

final class ArtistsTableViewController: NSViewController {
    fileprivate var artists: [Artist] = []
    var actions = ArtistActions()
    var onSelectionChange: ((Artist.ID?) -> Void)?
    var accentNSColor: NSColor = .controlAccentColor {
        didSet {
            guard accentNSColor != oldValue, isViewLoaded else { return }
            tableView.enumerateAvailableRowViews { rowView, _ in
                (rowView as? AccentSelectionRowView)?.selectionColor = accentNSColor
                rowView.needsDisplay = true
            }
        }
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    /// Set while pushing a selection down from SwiftUI, so the resulting delegate
    /// callback doesn't echo the same value back up and fight the binding.
    private var isApplyingExternalSelection = false

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("artist"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        // .none so AccentSelectionRowView's pill is what paints — the default would
        // draw the system accent over it, leaving this the one blue list in the app.
        tableView.selectionHighlightStyle = .none
        // 28 was tight for a single line of 13pt text; the list read as dense.
        tableView.rowHeight = 34
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.backgroundColor = .clear
        // No grid mask: AppKit rules every row edge to edge, which made a plain list of
        // names look like a spreadsheet. AccentSelectionRowView draws an inset hairline
        // instead — still a rail for the eye, but it stops short of the edges and skips
        // the selected row.
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.reserveSpaceForPlayerBar()
        view = scrollView
    }

    func apply(artists newArtists: [Artist], selection: Artist.ID?) {
        let changed = artists.map(\.id) != newArtists.map(\.id)
        artists = newArtists
        if changed { tableView.reloadData() }

        let targetRow = selection.flatMap { id in artists.firstIndex(where: { $0.id == id }) }
        let currentRow = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
        guard targetRow != currentRow else { return }

        isApplyingExternalSelection = true
        if let targetRow {
            tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(targetRow)
        } else {
            tableView.deselectAll(nil)
        }
        isApplyingExternalSelection = false
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard artists.indices.contains(row) else { return }
        actions.play(artists[row])
    }

    /// Right-clicking an unselected row acts on that row, and adopts it as the selection
    /// so the detail pane matches what the menu is about to act on.
    private func artistForContextAction() -> Artist? {
        let clicked = tableView.clickedRow
        guard artists.indices.contains(clicked) else { return nil }
        if tableView.selectedRow != clicked {
            tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        }
        return artists[clicked]
    }

    @objc private func menuPlay() { withContextArtist { actions.play($0) } }
    @objc private func menuShuffle() { withContextArtist { actions.shuffle($0) } }
    @objc private func menuPlayNext() { withContextArtist { actions.playNext($0) } }
    @objc private func menuAddToEnd() { withContextArtist { actions.addToEnd($0) } }
    @objc private func menuAddToPlaylist() { withContextArtist { actions.addToPlaylist($0) } }
    @objc private func menuDownload() { withContextArtist { actions.download($0) } }
    @objc private func menuRemoveDownload() { withContextArtist { actions.removeDownload($0) } }

    private func withContextArtist(_ body: (Artist) -> Void) {
        guard let artist = artistForContextAction() else { return }
        body(artist)
    }
}

extension ArtistsTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { artists.count }
}

extension ArtistsTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard artists.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ArtistCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)
        cell.textField?.stringValue = artists[row].name
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = AccentSelectionRowView()
        view.selectionColor = accentNSColor
        // Matches the 10pt margin `style = .inset` gives the rows; the row separators
        // are NSTableView's own grid lines here, so no hairline of our own.
        view.customSelectionLeftInset = 10
        view.customSelectionRightInset = 10
        view.suppressDivider = false
        return view
    }

    /// Gives NSTableView's built-in type-to-select something to match against.
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        artists.indices.contains(row) ? artists[row].name : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // selectionHighlightStyle = .none means NSTableView won't redraw rows itself.
        tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
        guard !isApplyingExternalSelection else { return }
        let row = tableView.selectedRow
        onSelectionChange?(artists.indices.contains(row) ? artists[row].id : nil)
    }

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

extension ArtistsTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let artist = artists.indices.contains(tableView.clickedRow) ? artists[tableView.clickedRow] : nil else { return }

        addItem(to: menu, title: "Play", action: #selector(menuPlay))
        addItem(to: menu, title: "Shuffle", action: #selector(menuShuffle))
        menu.addItem(.separator())
        addItem(to: menu, title: "Play Next", action: #selector(menuPlayNext))
        addItem(to: menu, title: "Add to Queue", action: #selector(menuAddToEnd))
        menu.addItem(.separator())
        addItem(to: menu, title: "Add to Playlist…", action: #selector(menuAddToPlaylist))
        if actions.supportsDownload {
            menu.addItem(.separator())
            if actions.isFullyDownloaded(artist) {
                addItem(to: menu, title: "Remove Download", action: #selector(menuRemoveDownload))
            } else {
                addItem(to: menu, title: "Download", action: #selector(menuDownload))
            }
        }
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
}
#endif
