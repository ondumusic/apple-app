#if os(macOS)
import AppKit
import Nuke
import SwiftUI

/// AppKit-backed artist list. A SwiftUI `List` consumes the double-click that means
/// "play" everywhere else on the Mac, and gives no type-to-select; NSTableView provides
/// both natively, and matches how the tracks tables are already built.
struct ArtistsTable: NSViewControllerRepresentable {
    let artists: [Artist]
    @Binding var selection: Artist.ID?
    let actions: ArtistActions
    let accent: Color
    var showsArtwork: Bool = true
    /// Room for chrome floating over the top of the list, which rows scroll under.
    var topContentInset: CGFloat = 0

    func makeNSViewController(context: Context) -> ArtistsTableViewController {
        let vc = ArtistsTableViewController()
        vc.accentNSColor = NSColor(accent)
        vc.actions = actions
        vc.onSelectionChange = { selection = $0 }
        vc.showsArtwork = showsArtwork
        vc.topContentInset = topContentInset
        vc.apply(artists: artists, selection: selection)
        return vc
    }

    func updateNSViewController(_ vc: ArtistsTableViewController, context: Context) {
        vc.accentNSColor = NSColor(accent)
        vc.actions = actions
        vc.onSelectionChange = { selection = $0 }
        vc.showsArtwork = showsArtwork
        vc.topContentInset = topContentInset
        vc.apply(artists: artists, selection: selection)
    }
}

final class ArtistsTableViewController: NSViewController {
    fileprivate var artists: [Artist] = []
    var actions = ArtistActions()
    var onSelectionChange: ((Artist.ID?) -> Void)?
    var topContentInset: CGFloat = 0 {
        didSet {
            guard topContentInset != oldValue, isViewLoaded else { return }
            scrollView.setTopContentInset(topContentInset)
        }
    }
    var showsArtwork: Bool = true {
        didSet {
            guard showsArtwork != oldValue, isViewLoaded else { return }
            applyDensity()
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

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    /// Set while pushing a selection down from SwiftUI, so the resulting delegate
    /// callback doesn't echo the same value back up and fight the binding.
    private var isApplyingExternalSelection = false

    override func viewDidAppear() {
        super.viewDidAppear()
        tableView.claimKeyboardFocus()
    }

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
        applyRowHeight()
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
        // Drag source only — an artist can be dropped into Up Next or onto a playlist,
        // but the list's order is the library's and isn't the user's to rearrange.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.setTopContentInset(topContentInset)
        scrollView.addBottomContentPadding()
        view = scrollView
    }

    func apply(artists newArtists: [Artist], selection: Artist.ID?) {
        let changed = artists.map(\.id) != newArtists.map(\.id)
        artists = newArtists
        if changed {
            tableView.reloadData()
        } else {
            // The set is the same but a row's contents may not be — artwork arrives
            // without the list changing shape, and a reload here would fight scrolling.
            refreshVisibleCells()
        }

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
    @objc private func menuChooseArtwork() { withContextArtist { actions.chooseArtwork($0) } }
    @objc private func menuRemoveArtwork() { withContextArtist { actions.removeArtwork($0) } }

    private func withContextArtist(_ body: (Artist) -> Void) {
        guard let artist = artistForContextAction() else { return }
        body(artist)
    }
}

extension ArtistsTableViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { artists.count }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard artists.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(artists[row].id.uuidString, forType: .onduArtists)
        return item
    }
}

extension ArtistsTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard artists.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ArtistCell")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: self) as? ArtistCell
            ?? ArtistCell(identifier: identifier)
        cell.show(artists[row], showsArtwork: showsArtwork)
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

    private var rowHeightForDensity: CGFloat { showsArtwork ? 50 : 34 }

    private func applyRowHeight() {
        // Taller only when there's a circle to fit: without one this is the compact list
        // it has always been.
        tableView.rowHeight = rowHeightForDensity
    }

    /// Reloading would rebuild every cell and cut straight to the new height. Telling the
    /// table its rows changed height animates it, and the cells it already has can be
    /// reconfigured where they stand — they know how to draw either density.
    private func refreshVisibleCells() {
        guard isViewLoaded else { return }
        tableView.enumerateAvailableRowViews { rowView, row in
            guard artists.indices.contains(row),
                let cell = rowView.view(atColumn: 0) as? ArtistCell
            else { return }
            cell.show(artists[row], showsArtwork: showsArtwork)
        }
    }

    private func applyDensity() {
        tableView.rowHeight = rowHeightForDensity
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<max(artists.count, 0)))
        }
        tableView.enumerateAvailableRowViews { rowView, row in
            guard artists.indices.contains(row),
                let cell = rowView.view(atColumn: 0) as? ArtistCell
            else { return }
            cell.show(artists[row], showsArtwork: showsArtwork)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeightForDensity
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

}

/// TEMPORARY: a thumbnail in the artists list, to see whether it belongs there.
private final class ArtistCell: NSTableCellView {
    private static let diameter: CGFloat = 34

    private let thumbnail = ArtistThumbnailView()
    private var shownIdentity: String?
    private var loadTask: Task<Void, Never>?
    private var textLeadingWithArtwork: NSLayoutConstraint!
    private var textLeadingPlain: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnail)

        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        textField = field

        textLeadingWithArtwork = field.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8)
        textLeadingPlain = field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: Self.diameter),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor),
            textLeadingWithArtwork,
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { thumbnail.isEmphasized = backgroundStyle == .emphasized }
    }

    func show(_ artist: Artist, showsArtwork: Bool) {
        textField?.stringValue = artist.name
        thumbnail.isHidden = !showsArtwork
        textLeadingWithArtwork.isActive = showsArtwork
        textLeadingPlain.isActive = !showsArtwork
        guard showsArtwork else {
            loadTask?.cancel()
            shownIdentity = nil
            return
        }
        // Keyed on the artwork as well as the artist: an upload replaces the URL under
        // the same id, and keying on the id alone left the old picture in place until
        // the app restarted.
        let identity = "\(artist.id)|\(artist.artwork.first?.url.absoluteString ?? "")"
        guard shownIdentity != identity else { return }
        shownIdentity = identity
        loadTask?.cancel()
        showGlyph()

        guard let variant = artist.artwork.covering(pixelWidth: ArtworkSize.medium.pixels) else { return }
        let wanted = identity
        loadTask = Task { [weak self] in
            // The shared bucket rather than this cell's own size: a resize of its own
            // would be a second cache entry and a second decode of the same picture the
            // rest of the app already has.
            let request = ImageRequest(
                url: variant.url,
                processors: [.resize(width: CGFloat(ArtworkSize.thumbnail.pixels))])
            guard let image = try? await ImagePipeline.shared.image(for: request),
                !Task.isCancelled, let self, self.shownIdentity == wanted
            else { return }
            self.thumbnail.image = image
        }
    }

    private func showGlyph() {
        thumbnail.image = nil
    }
}

/// Draws its own circle rather than relying on a layer radius over a view's bounds.
///
/// Two attempts at the latter produced eggs and rounded squares: an NSImageView in a
/// table cell doesn't necessarily end up the size its constraints ask for, and a radius
/// of half the height on a view that isn't square is a pill. Inscribing the circle in the
/// largest square the bounds allow can't be wrong whatever the view's shape turns out to
/// be.
private final class ArtistThumbnailView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    /// On a selected row the fill is the accent colour, so an accent glyph on a grey disc
    /// reads as a hole punched in it. White on a wash of white is what the text beside it
    /// does.
    var isEmphasized = false {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let circle = NSRect(
            x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
            width: side, height: side)
        let path = NSBezierPath(ovalIn: circle)

        guard let image else {
            (isEmphasized ? NSColor.white.withAlphaComponent(0.22) : .quaternaryLabelColor).setFill()
            path.fill()
            drawGlyph(in: circle)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: aspectFill(image.size, in: circle))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGlyph(in circle: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: circle.height * 0.38, weight: .regular)
        guard
            let glyph = NSImage(systemSymbolName: "music.mic", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)?
                .tinted(isEmphasized ? .white : .controlAccentColor)
        else { return }
        let size = glyph.size
        glyph.draw(
            in: NSRect(
                x: circle.midX - size.width / 2, y: circle.midY - size.height / 2,
                width: size.width, height: size.height))
    }

    /// Fills the circle and centres the overflow, rather than letterboxing a photo that
    /// isn't square — which artist artwork never is.
    private func aspectFill(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let scaled = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: rect.midX - scaled.width / 2, y: rect.midY - scaled.height / 2,
            width: scaled.width, height: scaled.height)
    }
}

extension NSImage {
    fileprivate func tinted(_ color: NSColor) -> NSImage {
        let copy = NSImage(size: size)
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceOver)
        draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .destinationIn, fraction: 1)
        copy.unlockFocus()
        return copy
    }
}

extension ArtistsTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let artist = artists.indices.contains(tableView.clickedRow) ? artists[tableView.clickedRow] : nil else {
            return
        }

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
        if actions.supportsArtwork, showsArtwork {
            menu.addItem(.separator())
            addItem(
                to: menu,
                title: artist.artwork.isEmpty ? "Choose Artwork…" : "Replace Artwork…",
                action: #selector(menuChooseArtwork))
            if !artist.artwork.isEmpty {
                addItem(to: menu, title: "Remove Artwork", action: #selector(menuRemoveArtwork))
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
