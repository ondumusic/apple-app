#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI bridge for the AppKit sidebar. Wraps a SidebarViewController that owns the
/// NSOutlineView and its data source/delegate. Selection is the only piece of state
/// exposed back to SwiftUI for now — folders, drag/drop, rename land in subsequent
/// commits.
struct Sidebar: NSViewControllerRepresentable {
    @Binding var selection: SidebarSelection?
    let musicLibrary: MusicLibrary
    let actions: SidebarActions

    func makeNSViewController(context: Context) -> SidebarViewController {
        let vc = SidebarViewController()
        vc.onSelectionChange = { newValue in
            selection = newValue
        }
        vc.actions = actions
        return vc
    }

    func updateNSViewController(_ nsViewController: SidebarViewController, context: Context) {
        // Rebuild the tree from the current library state. allPlaylists() is one fetch;
        // we group by parentId in-memory to materialize the folder hierarchy.
        nsViewController.actions = actions
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
    var actions: SidebarActions = SidebarActions()

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))

    private var rootNodes: [SidebarNode] = []
    private var librarySection: SidebarNode!
    private var playlistsSection: SidebarNode!

    /// Set when we're applying an externally-driven selection so we can suppress the
    /// callback that would otherwise echo it back through the binding.
    private var suppressSelectionCallback = false

    override func loadView() {
        view = NSView()

        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false

        column.resizingMask = [.autoresizingMask, .userResizingMask]
        column.minWidth = 100
        column.width = 220
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        outlineView.dataSource = self
        outlineView.delegate = self

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        buildSkeletonTree()
        outlineView.reloadData()
        outlineView.expandItem(librarySection)
        outlineView.expandItem(playlistsSection)
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
        cell.identifier = SidebarCell.identifier
        cell.configure(for: node)
        return cell
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

// MARK: - Context Menu

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? SidebarNode,
              case .playlist(let playlist) = node.kind
        else { return }

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
    }

    @objc private func menuPlay(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.playPlaylist(playlist) }
    }

    @objc private func menuShuffle(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.shufflePlaylist(playlist) }
    }

    @objc private func menuRename(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.renamePlaylist(playlist) }
    }

    @objc private func menuDelete(_ sender: NSMenuItem) {
        if let playlist = sender.representedObject as? Playlist { actions.deletePlaylist(playlist) }
    }
}

// MARK: - Cell

private final class SidebarCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarCell")

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var labelLeadingToIcon: NSLayoutConstraint!
    private var labelLeadingToCell: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        addSubview(icon)
        imageView = icon

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        textField = label

        labelLeadingToIcon = label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6)
        // For section headers: pin label directly to cell leading so it visually aligns
        // with where children's icons sit (children are indented one level by NSOutlineView).
        labelLeadingToCell = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelLeadingToIcon,
        ])
    }

    func configure(for node: SidebarNode) {
        switch node.kind {
        case .section(let title):
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
        }
    }
}
#endif
