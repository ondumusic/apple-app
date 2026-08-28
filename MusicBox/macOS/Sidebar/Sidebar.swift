#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI bridge for the AppKit sidebar. Wraps a SidebarViewController that owns the
/// NSOutlineView and its data source/delegate. Selection is the only piece of state
/// exposed back to SwiftUI for now — folders, drag/drop, rename land in subsequent
/// commits.
struct Sidebar: NSViewControllerRepresentable {
    @Binding var selection: SidebarSelection?
    @Binding var searchText: String
    let musicLibrary: MusicLibrary
    let actions: SidebarActions
    /// Active + queued downloads — surfaces as a badge on the Downloads category cell.
    var downloadingCount: Int = 0
    /// Library scope. Lives here rather than the window toolbar: it filters the library
    /// the sidebar navigates, and the toolbar is the player's.
    @Binding var filter: LibraryFilter
    /// The app accent. .sourceList selection would otherwise paint the system accent,
    /// the way the track tables used to.
    var accent: Color = .accentColor

    func makeNSViewController(context: Context) -> SidebarViewController {
        let vc = SidebarViewController()
        vc.onSelectionChange = { newValue in
            selection = newValue
        }
        vc.onSearchTextChange = { newText in
            searchText = newText
        }
        vc.actions = actions
        vc.onFilterChange = { filter = $0 }
        return vc
    }

    func updateNSViewController(_ nsViewController: SidebarViewController, context: Context) {
        // Rebuild the tree from the current library state. allPlaylists() is one fetch;
        // we group by parentId in-memory to materialize the folder hierarchy.
        nsViewController.actions = actions
        nsViewController.onFilterChange = { filter = $0 }
        nsViewController.accentNSColor = NSColor(accent)
        nsViewController.applyFilter(filter)
        nsViewController.applyExternalSearchText(searchText)
        nsViewController.applyDownloadingCount(downloadingCount)
        let nodes = Self.buildPlaylistTree(allPlaylists: musicLibrary.allPlaylists())
        nsViewController.update(playlistNodes: nodes, externalSelection: selection)
    }

    private static func buildPlaylistTree(allPlaylists: [Playlist]) -> [SidebarNode] {
        let byParent = Dictionary(grouping: allPlaylists, by: { $0.parentId })
        func makeNodes(parent: UUID?) -> [SidebarNode] {
            let kids = (byParent[parent] ?? []).sorted { a, b in
                if a.isFolder != b.isFolder { return a.isFolder && !b.isFolder }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return kids.map { playlist in
                let children = playlist.isFolder ? makeNodes(parent: playlist.id) : []
                return SidebarNode(kind: .playlist(playlist), children: children)
            }
        }
        return makeNodes(parent: nil)
    }
}

// MARK: - Tree model

/// NSObject so NSOutlineView can use reference identity for items.
final class SidebarNode: NSObject {
    enum Kind {
        case section(title: String)
        case category(SidebarCategory)
        case playlist(Playlist)
    }

    let kind: Kind
    var children: [SidebarNode]

    init(kind: Kind, children: [SidebarNode] = []) {
        self.kind = kind
        self.children = children
    }

    var selectionId: SidebarSelection? {
        switch kind {
        case .section: nil
        case .category(let c): .category(c)
        case .playlist(let p): .playlist(p.id)
        }
    }

    var isGroupHeader: Bool {
        if case .section = kind { return true }
        return false
    }
}

// MARK: - View Controller

final class SidebarViewController: NSViewController {
    var onSelectionChange: ((SidebarSelection?) -> Void)?
    var onSearchTextChange: ((String) -> Void)?
    var actions: SidebarActions = SidebarActions()

    private let scrollView = NSScrollView()
    private let outlineView = KeyAwareOutlineView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    private let searchField = NSSearchField()
    private let filterControl = NSSegmentedControl(
        labels: ["All", "Downloaded"], trackingMode: .selectOne, target: nil, action: nil
    )
    var onFilterChange: ((LibraryFilter) -> Void)?
    /// See TracksTable: cached at configure time, so a change needs an explicit repaint.
    var accentNSColor: NSColor = .controlAccentColor {
        didSet {
            guard accentNSColor != oldValue, isViewLoaded else { return }
            outlineView.enumerateAvailableRowViews { rowView, row in
                (rowView as? SidebarRowView)?.selectionColor = accentNSColor
                (rowView.view(atColumn: 0) as? SidebarCell)?.accentColor = accentNSColor
                rowView.needsDisplay = true
            }
        }
    }
    private let addButton = NSButton()
    private let bottomBar = NSView()

    private var rootNodes: [SidebarNode] = []
    private var librarySection: SidebarNode!
    private var playlistsSection: SidebarNode!
    /// Active + queued downloads. Surfaced as a numeric badge on the Downloads category
    /// cell when > 0.
    private var downloadingCount: Int = 0

    func applyDownloadingCount(_ count: Int) {
        guard count != downloadingCount else { return }
        downloadingCount = count
        // Find and reload just the .downloads category row so the badge refreshes
        // without disturbing other rows or selection.
        guard let library = librarySection else { return }
        for child in library.children {
            if case .category(let cat) = child.kind, cat == .downloads {
                outlineView.reloadItem(child)
                break
            }
        }
    }

    /// Set when we're applying an externally-driven selection so we can suppress the
    /// callback that would otherwise echo it back through the binding.
    private var suppressSelectionCallback = false
    /// Inline rename request that arrived before the row was in the outline view (the
    /// new playlist hadn't been picked up by the next tree rebuild yet). We trigger as
    /// soon as the row appears in update().
    private var pendingInlineRenameId: UUID?

    override func loadView() {
        view = NSView()

        outlineView.headerView = nil
        outlineView.style = .sourceList
        // .none so our own accent pill paints; .sourceList always uses the system accent.
        outlineView.selectionHighlightStyle = .none
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        // Per-section indenting is overridden in the cell — see shouldCompensateIndent.
        // We keep the global indent at the file-level constant so folders with disclosure
        // triangles still have room.
        outlineView.indentationPerLevel = indentationPerLevel

        column.resizingMask = [.autoresizingMask, .userResizingMask]
        column.minWidth = 100
        column.width = 220
        column.isEditable = true
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.onDelete = { [weak self] in self?.deleteSelectedPlaylist() }

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        outlineView.registerForDraggedTypes([.musicBoxTracks, .musicBoxSidebarPlaylist])
        outlineView.draggingDestinationFeedbackStyle = .regular
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        searchField.placeholderString = "Search"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New")
        addButton.bezelStyle = .accessoryBar
        addButton.isBordered = false
        addButton.target = self
        addButton.action = #selector(showAddMenu(_:))
        addButton.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(addButton)
        filterControl.segmentStyle = .capsule
        filterControl.controlSize = .small
        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(filterControl)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            // Window toolbar sits above us already; no need to reserve space for traffic
            // lights here.
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 34),
            addButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 6),
            addButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 22),
            addButton.heightAnchor.constraint(equalToConstant: 22),
            filterControl.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -6),
            filterControl.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFocusSearch),
            name: .focusSearch,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartInlineRename(_:)),
            name: .startInlineRename,
            object: nil
        )

        buildSkeletonTree()
        outlineView.reloadData()
        outlineView.expandItem(librarySection)
        outlineView.expandItem(playlistsSection)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Without this, the NSSearchField is the window's first focusable view and
        // the system parks the keyboard focus there on launch — annoying because the
        // user usually wants to navigate the sidebar with arrow keys, not type a search
        // they didn't ask for.
        if view.window?.firstResponder === searchField || view.window?.firstResponder === view.window {
            view.window?.makeFirstResponder(outlineView)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // NSOutlineView's columnAutoresizingStyle doesn't always re-tile on the very
        // first layout pass — the column keeps its declared width (220pt) which can
        // exceed the initial clipView width and produce a horizontal scroll until the
        // user resizes the split. sizeLastColumnToFit() forces the column to match
        // the visible area on every layout.
        outlineView.sizeLastColumnToFit()
    }

    func applyExternalSearchText(_ text: String) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    func applyFilter(_ filter: LibraryFilter) {
        let index = filter == .downloaded ? 1 : 0
        if filterControl.selectedSegment != index { filterControl.selectedSegment = index }
    }

    @objc private func filterChanged() {
        onFilterChange?(filterControl.selectedSegment == 1 ? .downloaded : .all)
    }

    @objc private func searchFieldChanged() {
        onSearchTextChange?(searchField.stringValue)
    }

    @objc private func handleFocusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    private func deleteSelectedPlaylist() {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              case .playlist(let playlist) = node.kind
        else { return }
        actions.deletePlaylist(playlist)
    }

    @objc private func handleStartInlineRename(_ notification: Notification) {
        guard let id = notification.object as? UUID else { return }
        let immediateRow = rowForSelection(.playlist(id))
        #if DEBUG
        print("[rename] handleStartInlineRename id=\(id) immediateRow=\(immediateRow as Any)")
        #endif
        if immediateRow != nil {
            DispatchQueue.main.async { [weak self] in
                self?.startInlineRename(playlistId: id)
            }
        } else {
            pendingInlineRenameId = id
        }
    }

    private func startInlineRename(playlistId: UUID) {
        guard let row = rowForSelection(.playlist(playlistId)) else {
            #if DEBUG
            print("[rename] startInlineRename: no row for \(playlistId)")
            #endif
            return
        }
        #if DEBUG
        print("[rename] startInlineRename row=\(row)")
        #endif
        outlineView.scrollRowToVisible(row)
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let window = self.view.window else {
                #if DEBUG
                print("[rename] no window")
                #endif
                return
            }
            guard let row = self.rowForSelection(.playlist(playlistId)) else {
                #if DEBUG
                print("[rename] row vanished by 50ms")
                #endif
                return
            }
            guard let cellRaw = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) else {
                #if DEBUG
                print("[rename] view(atColumn:row:) returned nil row=\(row)")
                #endif
                return
            }
            guard let cell = cellRaw as? SidebarCell else {
                #if DEBUG
                print("[rename] cell not SidebarCell, got \(type(of: cellRaw))")
                #endif
                return
            }
            #if DEBUG
            print("[rename] window.isKey=\(window.isKeyWindow) firstResponder=\(window.firstResponder.map { String(describing: $0) } ?? "nil")")
            #endif
            if !window.isKeyWindow { window.makeKey() }
            cell.beginInlineRename()
        }
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        let menu = NSMenu()

        // Drop new entry inside the currently-selected folder if one's selected;
        // otherwise root.
        let parentId: UUID? = {
            let row = outlineView.selectedRow
            guard row >= 0,
                  let node = outlineView.item(atRow: row) as? SidebarNode,
                  case .playlist(let p) = node.kind,
                  p.isFolder
            else { return nil }
            return p.id
        }()

        let newPlaylist = NSMenuItem(title: "New Playlist", action: #selector(menuNewPlaylist(_:)), keyEquivalent: "")
        newPlaylist.target = self
        newPlaylist.representedObject = parentId as Any?
        menu.addItem(newPlaylist)

        let newFolder = NSMenuItem(title: "New Folder", action: #selector(menuNewFolder(_:)), keyEquivalent: "")
        newFolder.target = self
        newFolder.representedObject = parentId as Any?
        menu.addItem(newFolder)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }

    @objc private func menuNewPlaylist(_ sender: NSMenuItem) {
        actions.createPlaylist(sender.representedObject as? UUID)
    }

    @objc private func menuNewFolder(_ sender: NSMenuItem) {
        actions.createFolder(sender.representedObject as? UUID)
    }

    /// Rebuilds the playlist branch and applies any external selection change. Tries to
    /// preserve expansion state across reloads — only the children of the playlists
    /// section change, so we reload that subtree, not the whole view.
    func update(playlistNodes: [SidebarNode], externalSelection: SidebarSelection?) {
        let expandedFolderIds = capturedExpandedFolderIds()
        let changed = !nodeTreesMatch(playlistsSection.children, playlistNodes)
        if changed {
            playlistsSection.children = playlistNodes
            outlineView.reloadItem(playlistsSection, reloadChildren: true)
            outlineView.expandItem(playlistsSection)
            restoreExpansion(matching: expandedFolderIds, in: playlistsSection)
        }
        applyExternalSelection(externalSelection)
        if let id = pendingInlineRenameId, rowForSelection(.playlist(id)) != nil {
            pendingInlineRenameId = nil
            #if DEBUG
            print("[rename] pending->fire id=\(id)")
            #endif
            DispatchQueue.main.async { [weak self] in
                self?.startInlineRename(playlistId: id)
            }
        }
    }

    private func capturedExpandedFolderIds() -> Set<UUID> {
        var ids: Set<UUID> = []
        func walk(_ nodes: [SidebarNode]) {
            for node in nodes {
                if case .playlist(let p) = node.kind, p.isFolder, outlineView.isItemExpanded(node) {
                    ids.insert(p.id)
                }
                walk(node.children)
            }
        }
        walk(playlistsSection.children)
        return ids
    }

    private func restoreExpansion(matching ids: Set<UUID>, in section: SidebarNode) {
        func walk(_ nodes: [SidebarNode]) {
            for node in nodes {
                if case .playlist(let p) = node.kind, p.isFolder, ids.contains(p.id) {
                    outlineView.expandItem(node)
                }
                walk(node.children)
            }
        }
        walk(section.children)
    }

    private func buildSkeletonTree() {
        librarySection = SidebarNode(
            kind: .section(title: "Library"),
            children: SidebarCategory.allCases.map { SidebarNode(kind: .category($0)) }
        )
        playlistsSection = SidebarNode(kind: .section(title: "Playlists"))
        rootNodes = [librarySection, playlistsSection]
    }

    private func nodeTreesMatch(_ a: [SidebarNode], _ b: [SidebarNode]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            guard lhs.selectionId == rhs.selectionId else { return false }
            if case .playlist(let lp) = lhs.kind, case .playlist(let rp) = rhs.kind {
                if lp.name != rp.name { return false }
                if lp.isFolder != rp.isFolder { return false }
            }
            if !nodeTreesMatch(lhs.children, rhs.children) { return false }
        }
        return true
    }

    private func applyExternalSelection(_ selection: SidebarSelection?) {
        guard let selection else {
            if outlineView.selectedRow != -1 {
                suppressSelectionCallback = true
                outlineView.deselectAll(nil)
                suppressSelectionCallback = false
            }
            return
        }
        guard let row = rowForSelection(selection) else { return }
        if outlineView.selectedRow == row { return }
        suppressSelectionCallback = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressSelectionCallback = false
    }

    private func rowForSelection(_ selection: SidebarSelection) -> Int? {
        for index in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: index) as? SidebarNode else { continue }
            if node.selectionId == selection { return index }
        }
        return nil
    }
}

// MARK: - NSOutlineViewDataSource

extension SidebarViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNodes.count }
        return (item as? SidebarNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNodes[index] }
        return (item as! SidebarNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        // Sections are expandable when they have content; folders are always expandable
        // (so the disclosure triangle shows even on an empty folder, matching Apple Music).
        switch node.kind {
        case .section: return !node.children.isEmpty
        case .category: return false
        case .playlist(let p): return p.isFolder
        }
    }

    // MARK: - Drag source (sidebar playlist reorder)

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? SidebarNode, case .playlist(let p) = node.kind else { return nil }
        let pbItem = NSPasteboardItem()
        pbItem.setString(p.id.uuidString, forType: .musicBoxSidebarPlaylist)
        return pbItem
    }

    // MARK: - Drag/drop validation + accept

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if let trackOp = validateTrackDrop(info: info, item: item, index: index) { return trackOp }
        if let moveOp = validatePlaylistMoveDrop(info: info, item: item, index: index) { return moveOp }
        return []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        if acceptTrackDrop(info: info, item: item) { return true }
        if acceptPlaylistMoveDrop(info: info, item: item) { return true }
        return false
    }

    private func validateTrackDrop(info: NSDraggingInfo, item: Any?, index: Int) -> NSDragOperation? {
        guard let pasteboard = info.draggingPasteboard.pasteboardItems,
              pasteboard.contains(where: { $0.string(forType: .musicBoxTracks) != nil })
        else { return nil }
        // Only accept drops directly onto a non-folder playlist row.
        guard let node = item as? SidebarNode,
              case .playlist(let playlist) = node.kind,
              !playlist.isFolder,
              index == NSOutlineViewDropOnItemIndex
        else { return [] }
        _ = playlist
        return .copy
    }

    private func acceptTrackDrop(info: NSDraggingInfo, item: Any?) -> Bool {
        guard let node = item as? SidebarNode,
              case .playlist(let playlist) = node.kind,
              !playlist.isFolder
        else { return false }
        let trackIds: [UUID] = (info.draggingPasteboard.pasteboardItems ?? []).compactMap { item in
            guard let s = item.string(forType: .musicBoxTracks) else { return nil }
            return UUID(uuidString: s)
        }
        guard !trackIds.isEmpty else { return false }
        actions.addTracksToPlaylist(trackIds, playlist)
        return true
    }

    private func validatePlaylistMoveDrop(info: NSDraggingInfo, item: Any?, index: Int) -> NSDragOperation? {
        guard let pasteboard = info.draggingPasteboard.pasteboardItems,
              let raw = pasteboard.first(where: { $0.string(forType: .musicBoxSidebarPlaylist) != nil })?
                  .string(forType: .musicBoxSidebarPlaylist),
              let draggedId = UUID(uuidString: raw)
        else { return nil }

        let destinationParent = resolveDropTarget(item: item, index: index)
        // Reject self-drops and cycles (folder into its own descendant).
        if destinationParent == draggedId { return [] }
        if let dest = destinationParent, descendantIds(of: draggedId).contains(dest) { return [] }
        // Non-folder targets we treat as "drop alongside" — destinationParent already
        // equals that row's parent, which means it's a no-op move when source is at the
        // same level. That's fine; PlaylistController.movePlaylist guards same-parent.
        return .move
    }

    private func acceptPlaylistMoveDrop(info: NSDraggingInfo, item: Any?) -> Bool {
        guard let pasteboard = info.draggingPasteboard.pasteboardItems,
              let raw = pasteboard.first(where: { $0.string(forType: .musicBoxSidebarPlaylist) != nil })?
                  .string(forType: .musicBoxSidebarPlaylist),
              let draggedId = UUID(uuidString: raw)
        else { return false }
        let destinationParent = resolveDropTarget(item: item, index: -1)
        actions.movePlaylist(draggedId, destinationParent)
        return true
    }

    /// Map an outline-view drop target to the parentId we should move into.
    /// - Drop on a folder row → that folder's id
    /// - Drop on a non-folder row → that row's parentId (move alongside)
    /// - Drop on the Playlists section header or root → nil (root)
    private func resolveDropTarget(item: Any?, index: Int) -> UUID? {
        guard let node = item as? SidebarNode else { return nil }
        switch node.kind {
        case .section: return nil
        case .playlist(let p): return p.isFolder ? p.id : p.parentId
        case .category: return nil
        }
    }

    private func descendantIds(of playlistId: UUID) -> Set<UUID> {
        guard let node = findPlaylistNode(id: playlistId, in: playlistsSection.children) else { return [] }
        return collectDescendantIds(node)
    }

    private func findPlaylistNode(id: UUID, in nodes: [SidebarNode]) -> SidebarNode? {
        for node in nodes {
            if case .playlist(let p) = node.kind, p.id == id { return node }
            if let found = findPlaylistNode(id: id, in: node.children) { return found }
        }
        return nil
    }

    private func collectDescendantIds(_ node: SidebarNode) -> Set<UUID> {
        var out: Set<UUID> = []
        for child in node.children {
            if case .playlist(let p) = child.kind {
                out.insert(p.id)
                out.formUnion(collectDescendantIds(child))
            }
        }
        return out
    }
}

// MARK: - NSOutlineViewDelegate

extension SidebarViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.isGroupHeader ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.isGroupHeader
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }

        let cell = outlineView.makeView(withIdentifier: SidebarCell.identifier, owner: nil) as? SidebarCell
            ?? SidebarCell()
        cell.accentColor = accentNSColor
        cell.identifier = SidebarCell.identifier
        cell.renameDelegate = self
        let badge: Int? = {
            if case .category(let cat) = node.kind, cat == .downloads, downloadingCount > 0 {
                return downloadingCount
            }
            return nil
        }()
        cell.configure(for: node, compensateIndent: shouldCompensateIndent(for: node), badgeCount: badge)
        return cell
    }

    /// Per-section indent override. NSOutlineView applies one global indentationPerLevel,
    /// but the library section never wants any indent and the playlists section only wants
    /// indent when it actually has folders (to leave room for disclosure triangles).
    private func shouldCompensateIndent(for node: SidebarNode) -> Bool {
        switch parentSection(of: node) {
        case .library:
            return true   // always 0pt indent
        case .playlistsRoot:
            return !playlistsHaveAnyFolder
        case .deeper, .none:
            return false  // folder children keep their natural nesting indent
        }
    }

    private enum ParentSection {
        case library
        case playlistsRoot
        case deeper
        case none
    }

    private func parentSection(of node: SidebarNode) -> ParentSection {
        if librarySection.children.contains(where: { $0 === node }) { return .library }
        if playlistsSection.children.contains(where: { $0 === node }) { return .playlistsRoot }
        if isDescendant(node, of: playlistsSection) { return .deeper }
        return .none
    }

    private func isDescendant(_ node: SidebarNode, of root: SidebarNode) -> Bool {
        for child in root.children {
            if child === node { return true }
            if isDescendant(node, of: child) { return true }
        }
        return false
    }

    private var playlistsHaveAnyFolder: Bool {
        playlistsSection.children.contains {
            if case .playlist(let p) = $0.kind, p.isFolder { return true }
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let view = SidebarRowView()
        view.selectionColor = accentNSColor
        return view
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let node = item as? SidebarNode, case .section = node.kind {
            return 22
        }
        return 26
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if suppressSelectionCallback { return }
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode
        else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(node.selectionId)
    }
}

// MARK: - Inline rename

extension SidebarViewController: SidebarCellRenameDelegate {
    func sidebarCell(_ cell: NSTableCellView, commitRenameFor playlistId: UUID, newName: String) {
        // Resolve the current playlist from the outline tree (may have been updated since
        // the cell was last configured).
        guard let node = findPlaylistNode(id: playlistId, in: playlistsSection.children),
              case .playlist(let playlist) = node.kind
        else { return }
        if newName.isEmpty || newName == playlist.name {
            // Revert the field and skip the round-trip.
            cell.textField?.stringValue = playlist.name
            return
        }
        actions.renamePlaylist(playlist, newName)
    }

    func sidebarCellCancelRename(_ cell: NSTableCellView) {
        // Revert and end editing — caller's representedPlaylistId is still valid.
        let row = outlineView.row(for: cell)
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              case .playlist(let playlist) = node.kind
        else { return }
        cell.textField?.stringValue = playlist.name
        view.window?.makeFirstResponder(outlineView)
    }
}

// MARK: - Context Menu

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        let clickedPlaylist: Playlist? = {
            guard row >= 0,
                  let node = outlineView.item(atRow: row) as? SidebarNode,
                  case .playlist(let p) = node.kind
            else { return nil }
            return p
        }()

        if let playlist = clickedPlaylist {
            if !playlist.isFolder {
                let play = NSMenuItem(title: "Play", action: #selector(menuPlay), keyEquivalent: "")
                play.target = self
                play.representedObject = playlist
                menu.addItem(play)

                let shuffle = NSMenuItem(title: "Shuffle", action: #selector(menuShuffle), keyEquivalent: "")
                shuffle.target = self
                shuffle.representedObject = playlist
                menu.addItem(shuffle)

                menu.addItem(.separator())
            }

            let rename = NSMenuItem(title: "Rename", action: #selector(menuRename), keyEquivalent: "")
            rename.target = self
            rename.representedObject = playlist
            menu.addItem(rename)

            menu.addItem(.separator())

            let delete = NSMenuItem(
                title: playlist.isFolder ? "Delete Folder" : "Delete Playlist",
                action: #selector(menuDelete),
                keyEquivalent: ""
            )
            delete.target = self
            delete.representedObject = playlist
            menu.addItem(delete)

            if playlist.isFolder {
                menu.addItem(.separator())
                addCreateItems(to: menu, parentId: playlist.id)
            }
        } else {
            // Empty space, section header, or library category — offer to create at
            // root.
            addCreateItems(to: menu, parentId: nil)
        }
    }

    private func addCreateItems(to menu: NSMenu, parentId: UUID?) {
        let newPlaylist = NSMenuItem(title: "New Playlist", action: #selector(menuNewPlaylist(_:)), keyEquivalent: "")
        newPlaylist.target = self
        newPlaylist.representedObject = parentId as Any?
        menu.addItem(newPlaylist)

        let newFolder = NSMenuItem(title: "New Folder", action: #selector(menuNewFolder(_:)), keyEquivalent: "")
        newFolder.target = self
        newFolder.representedObject = parentId as Any?
        menu.addItem(newFolder)
    }

    @objc private func menuPlay(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.playPlaylist(playlist) }
    }

    @objc private func menuShuffle(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.shufflePlaylist(playlist) }
    }

    @objc private func menuRename(_ sender: NSMenuItem) {
        guard let playlist = sender.representedObject as? Playlist,
              let row = rowForSelection(.playlist(playlist.id))
        else { return }
        // Programmatic edit uses NSOutlineView's built-in inline editor on the outline
        // column. Cell rendering already gave the textField isEditable = true.
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func menuDelete(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.deletePlaylist(playlist) }
    }
}

// MARK: - Cell

/// Must match outlineView.indentationPerLevel — the cell uses this to compute the
/// negative offset that cancels NSOutlineView's indent for rows that shouldn't have it.
private let indentationPerLevel: CGFloat = 8

private final class SidebarCell: NSTableCellView {
    /// The app accent, for icons. Unselected they'd otherwise render in the system
    /// accent, which is the inconsistency the selection pill was fixing.
    var accentColor: NSColor = .controlAccentColor { didSet { applyEmphasis() } }
    private var isSectionHeader = false

    /// The cell used to get white-on-selection for free from NSTableCellView, because
    /// .sourceList told it when a row was highlighted. Drawing the pill ourselves means
    /// nothing does — so react to the style the row view hands down.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    private func applyEmphasis() {
        let emphasized = backgroundStyle == .emphasized
        if isSectionHeader {
            label.textColor = .secondaryLabelColor
            return
        }
        label.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
        icon.contentTintColor = emphasized ? .alternateSelectedControlTextColor : accentColor
        badge.textColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }

    static let identifier = NSUserInterfaceItemIdentifier("SidebarCell")

    private let icon = NSImageView()
    private let label = NSTextField()
    private var labelLeadingToIcon: NSLayoutConstraint!
    private var labelLeadingToCell: NSLayoutConstraint!
    /// Anchored to the cell's leading edge, but with a constant we can flip negative
    /// to compensate for NSOutlineView's per-level indent on rows that shouldn't have
    /// it (library categories, playlist roots when no folders exist).
    private var iconLeading: NSLayoutConstraint!
    /// Set when configured with a playlist node — used by the rename commit handler
    /// to map the edited text back to the right playlist via the outline view.
    var representedPlaylistId: UUID?
    weak var renameDelegate: SidebarCellRenameDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private let badge = NSTextField(labelWithString: "")

    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        addSubview(icon)
        imageView = icon

        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBordered = false
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false   // flipped on per-cell when editing
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.target = self
        label.action = #selector(commitRename(_:))
        label.delegate = self
        addSubview(label)
        textField = label

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        badge.textColor = .secondaryLabelColor
        badge.alignment = .right
        badge.isHidden = true
        addSubview(badge)

        labelLeadingToIcon = label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6)
        // For section headers: pin label directly to cell leading so it visually aligns
        // with where children's icons sit (children are indented one level by NSOutlineView).
        labelLeadingToCell = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)

        iconLeading = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)

        NSLayoutConstraint.activate([
            iconLeading,
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelLeadingToIcon,
        ])
    }

    func configure(for node: SidebarNode, compensateIndent: Bool = false, badgeCount: Int? = nil) {
        // Stay at NSOutlineView's natural indent for the row's depth — pulling icons
        // back with a negative offset (the previous behavior) overshot into the
        // selection pill's left inset, making icons hug the pill edge and sit left of
        // the section header text. compensateIndent is kept on the API for callers
        // but its only effect now is signaling intent.
        _ = compensateIndent
        iconLeading.constant = 0
        if let count = badgeCount, count > 0 {
            badge.stringValue = "\(count)"
            badge.isHidden = false
        } else {
            badge.isHidden = true
        }
        isSectionHeader = false
        switch node.kind {
        case .section(let title):
            isSectionHeader = true
            label.stringValue = title.uppercased()
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            icon.image = nil
            icon.isHidden = true
            labelLeadingToIcon.isActive = false
            labelLeadingToCell.isActive = true
        case .category(let cat):
            label.stringValue = cat.title
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            label.textColor = .labelColor
            icon.image = NSImage(systemSymbolName: cat.iconName, accessibilityDescription: cat.title)
            icon.isHidden = false
            labelLeadingToCell.isActive = false
            labelLeadingToIcon.isActive = true
        case .playlist(let playlist):
            let symbol = playlist.isFolder ? "folder" : "music.note.list"
            label.stringValue = playlist.name
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            label.textColor = .labelColor
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: playlist.name)
            icon.isHidden = false
            labelLeadingToCell.isActive = false
            labelLeadingToIcon.isActive = true
            representedPlaylistId = playlist.id
            label.isEditable = true   // editable so editColumn(...) starts inline edit
        }
        applyEmphasis()
    }

    @objc fileprivate func commitRename(_ sender: NSTextField) {
        guard let id = representedPlaylistId else { return }
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespaces)
        renameDelegate?.sidebarCell(self, commitRenameFor: id, newName: trimmed)
    }

    /// Direct entry into editing. selectText(_:) is NSTextField's canonical
    /// "begin editing" call — internally makes the field first responder, sets up the
    /// field editor, and selects all text. More reliable than makeFirstResponder +
    /// manual selectAll, which can leave the field editor in an indeterminate state
    /// when invoked right after a tree reload.
    func beginInlineRename() {
        label.isEditable = true
        label.isSelectable = true
        label.isBordered = false
        label.drawsBackground = false
        let beforeResponder = window?.firstResponder
        label.selectText(nil)
        let afterResponder = window?.firstResponder
        #if DEBUG
        print("[rename] beginInlineRename label.isEditable=\(label.isEditable) inWindow=\(window != nil) before=\(beforeResponder.map { String(describing: $0) } ?? "nil") after=\(afterResponder.map { String(describing: $0) } ?? "nil")")
        #endif
    }
}

extension SidebarCell: NSTextFieldDelegate {
    /// Escape during editing reverts the text and ends the edit without committing.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Revert the field back to the original name and end editing.
            renameDelegate?.sidebarCellCancelRename(self)
            return true
        }
        return false
    }
}

/// NSOutlineView subclass that fires onDelete on Backspace / forward Delete when the
/// selection isn't being inline-edited. Keeps the rest of NSOutlineView's keyDown
/// (arrow nav, expand/collapse) intact.
private final class KeyAwareOutlineView: NSOutlineView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 51 = delete (backspace), 117 = forward delete.
        if event.keyCode == 51 || event.keyCode == 117 {
            // Don't intercept when a cell text-editor is the first responder — let it
            // handle the keystroke normally.
            if let responder = window?.firstResponder, responder is NSText {
                super.keyDown(with: event)
                return
            }
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

protocol SidebarCellRenameDelegate: AnyObject {
    func sidebarCell(_ cell: NSTableCellView, commitRenameFor playlistId: UUID, newName: String)
    func sidebarCellCancelRename(_ cell: NSTableCellView)
}
/// Draws the source-list selection pill in the app's accent. NSOutlineView's own
/// .sourceList highlight always uses the system accent, which left the sidebar
/// disagreeing with every other surface.
private final class SidebarRowView: NSTableRowView {
    var selectionColor: NSColor = .selectedContentBackgroundColor

    override var isSelected: Bool {
        get { super.isSelected }
        set {
            guard newValue != super.isSelected else { return }
            super.isSelected = newValue
            // Repaint: without this the previous row keeps painting its pill, which is
            // how several rows ended up looking selected at once.
            needsDisplay = true
            let style: NSView.BackgroundStyle = newValue ? .emphasized : .normal
            for column in 0..<numberOfColumns {
                (view(atColumn: column) as? NSTableCellView)?.backgroundStyle = style
            }
        }
    }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    // Defers to super first so everything else the row draws — notably the drag
    // destination feedback the sidebar relies on for drops and reordering — still
    // happens; only the selection fill is ours.
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: 8, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        selectionColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    }

    /// Cells pick their text colour from this; with highlight style .none the default
    /// stays .normal even when selected, so labels would draw dark on the accent fill.
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}

#endif

