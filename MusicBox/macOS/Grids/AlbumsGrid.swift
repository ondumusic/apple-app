#if os(macOS)
import AppKit
import SwiftUI

/// AppKit-backed album grid. LazyVGrid gave no keyboard navigation (it has no focus
/// model for grid items), no rubber-band selection, and selection that lagged a click —
/// stacked tap gestures have to wait out the double-click interval before either can
/// fire. NSCollectionView selects on mouseDown and brings the rest with it, and it
/// recycles cells rather than keeping every realised card alive.
struct AlbumsGrid: NSViewControllerRepresentable {
    let albums: [Album]
    @Binding var selection: Set<Album.ID>
    let actions: AlbumActions
    let accent: Color
    let onOpen: (Album) -> Void
    /// Embedded in a taller scrolling page rather than owning the scroll. Drops the
    /// scroller and the elastic bounce so the wheel reaches the page behind it.
    var embedded: Bool = false

    func makeNSViewController(context: Context) -> AlbumsGridViewController {
        let vc = AlbumsGridViewController()
        apply(to: vc)
        return vc
    }

    func updateNSViewController(_ vc: AlbumsGridViewController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: AlbumsGridViewController) {
        vc.applyEmbedded(embedded)
        vc.accentNSColor = NSColor(accent)
        vc.actions = actions
        vc.onOpen = onOpen
        vc.onSelectionChange = { selection = $0 }
        vc.apply(albums: albums, selection: selection)
    }
}

final class AlbumsGridViewController: NSViewController {
    fileprivate var albums: [Album] = []
    var actions = AlbumActions()
    var onOpen: ((Album) -> Void)?
    var onSelectionChange: ((Set<Album.ID>) -> Void)?
    var accentNSColor: NSColor = .controlAccentColor {
        didSet {
            guard accentNSColor != oldValue, isViewLoaded else { return }
            applyItemChrome()
        }
    }

    private let collectionView = AlbumsCollectionView()
    private let scrollView = NSScrollView()
    /// Set while pushing a selection down from SwiftUI, so the resulting delegate
    /// callback doesn't echo the same value back up and fight the binding.
    private var isApplyingExternalSelection = false

    /// Matches the SwiftUI grid this replaced: cards stretch to fill the row, never
    /// narrower than this.
    static let minimumItemWidth: CGFloat = 160
    static let interitemSpacing: CGFloat = 16
    private static let lineSpacing: CGFloat = 20
    static let sectionInset: CGFloat = 20
    /// Title plus year plus the gap above them — the part of a cell that isn't artwork.
    static let captionHeight: CGFloat = 42

    /// How many cells fit across, for callers that trim their data to whole rows.
    static func columns(forWidth width: CGFloat) -> Int {
        let available = width - sectionInset * 2
        guard available > 0 else { return 1 }
        return max(1, Int((available + interitemSpacing) / (minimumItemWidth + interitemSpacing)))
    }

    /// Height of a grid showing `rows` rows at this width — what an embedded caller has
    /// to reserve, since the grid can't size itself inside a page that scrolls.
    static func height(forWidth width: CGFloat, rows: Int, embedded: Bool = false) -> CGFloat {
        let columns = CGFloat(columns(forWidth: width))
        let available = width - sectionInset * 2
        let itemWidth = max(minimumItemWidth,
                            floor((available - interitemSpacing * (columns - 1)) / columns))
        let itemHeight = itemWidth + captionHeight
        return CGFloat(rows) * itemHeight
            + CGFloat(max(0, rows - 1)) * lineSpacing
            + (embedded ? 0 : sectionInset * 2)
    }

    private var isEmbedded: Bool = false

    /// Re-applied on every update rather than only when the flag changes: the view can
    /// load either side of the first assignment, and a scroller created before it does
    /// isn't removed by setting the flag afterwards.
    func applyEmbedded(_ embedded: Bool) {
        isEmbedded = embedded
        guard isViewLoaded else { return }
        applyEmbeddedStyle()
    }

    private func applyEmbeddedStyle() {
        // hasVerticalScroller alone isn't enough when the system is set to show scroll
        // bars always: AppKit keeps a legacy 17pt scroller, which both shows as an empty
        // track and steals the width the item size was computed against.
        scrollView.scrollerStyle = isEmbedded ? .overlay : .legacy
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = !isEmbedded
        scrollView.verticalScrollElasticity = isEmbedded ? .none : .automatic
        scrollView.automaticallyAdjustsContentInsets = !isEmbedded
        if isEmbedded { scrollView.contentInsets = NSEdgeInsets() }
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout
        else { return }
        let vertical = isEmbedded ? 0 : Self.sectionInset
        layout.sectionInset = NSEdgeInsets(top: vertical, left: Self.sectionInset,
                                           bottom: vertical, right: Self.sectionInset)
    }

    override func loadView() {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Self.interitemSpacing
        layout.minimumLineSpacing = Self.lineSpacing
        layout.sectionInset = NSEdgeInsets(
            top: Self.sectionInset, left: Self.sectionInset,
            bottom: Self.sectionInset, right: Self.sectionInset
        )

        collectionView.collectionViewLayout = layout
        defer { applyEmbeddedStyle() }
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(AlbumGridItem.self, forItemWithIdentifier: AlbumGridItem.identifier)
        collectionView.onDoubleClick = { [weak self] indexPath in
            guard let self, self.albums.indices.contains(indexPath.item) else { return }
            self.onOpen?(self.albums[indexPath.item])
        }
        collectionView.onOpenSelection = { [weak self] in
            guard let self, let first = self.selectedAlbums().first else { return }
            self.onOpen?(first)
        }
        collectionView.onEmphasisChange = { [weak self] in self?.applyItemChrome() }
        collectionView.onHoverChange = { [weak self] path in self?.applyHover(path) }

        let menu = NSMenu()
        menu.delegate = self
        collectionView.menu = menu

        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        view = scrollView

        // Scrolling moves cells under a stationary cursor, which produces no mouse event
        // of its own — without this the play button stays on whichever cover the pointer
        // was over when the scroll started.
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.collectionView.refreshHoverFromPointer() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Last width the layout was invalidated for. Flow layout caches item sizes, so a
    /// width change has to invalidate explicitly — see sizeForItemAt below.
    private var lastLaidOutWidth: CGFloat = 0

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = collectionView.bounds.width
        guard width > 0, width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width
        collectionView.collectionViewLayout?.invalidateLayout()
    }

    /// Flow layout wants a fixed item size, so the adaptive-column arithmetic that
    /// `GridItem(.adaptive(minimum:))` did for us happens here instead.
    fileprivate func itemSize(forWidth width: CGFloat) -> NSSize {
        let available = width - Self.sectionInset * 2
        guard available > 0 else { return NSSize(width: Self.minimumItemWidth, height: Self.minimumItemWidth + Self.captionHeight) }
        let spacing = Self.interitemSpacing
        let columns = max(1, Int((available + spacing) / (Self.minimumItemWidth + spacing)))
        let itemWidth = floor((available - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return NSSize(width: itemWidth, height: itemWidth + Self.captionHeight)
    }

    func apply(albums newAlbums: [Album], selection: Set<Album.ID>) {
        let changed = albums.map(\.id) != newAlbums.map(\.id)
        albums = newAlbums
        if changed { collectionView.reloadData() }

        let target = Set(albums.indices.filter { selection.contains(albums[$0].id) }
            .map { IndexPath(item: $0, section: 0) })
        guard target != collectionView.selectionIndexPaths else { return }
        isApplyingExternalSelection = true
        collectionView.selectionIndexPaths = target
        isApplyingExternalSelection = false
    }

    fileprivate func selectedAlbums() -> [Album] {
        collectionView.selectionIndexPaths
            .map(\.item)
            .sorted()
            .compactMap { albums.indices.contains($0) ? albums[$0] : nil }
    }

    private var hoveredIndexPath: IndexPath?

    private func applyHover(_ path: IndexPath?) {
        guard path != hoveredIndexPath else { return }
        hoveredIndexPath = path
        for (index, item) in collectionView.visibleItems().enumerated() {
            _ = index
            guard let cell = item as? AlbumGridItem,
                  let itemPath = collectionView.indexPath(for: item) else { continue }
            cell.isHovered = itemPath == path
        }
    }

    private func applyItemChrome() {
        for item in collectionView.visibleItems().compactMap({ $0 as? AlbumGridItem }) {
            item.accentColor = accentNSColor
            item.isEmphasized = collectionView.isFirstResponderEmphasis
        }
    }

    private func publishSelection() {
        guard !isApplyingExternalSelection else { return }
        onSelectionChange?(Set(selectedAlbums().map(\.id)))
        scrollSelectionIntoEnclosingScrollView()
    }

    /// Embedded, the grid is sized to its content and has nothing to scroll, so arrowing
    /// to an item below the fold left it off screen. Ask the page's scroll view instead,
    /// and only while the grid has focus — a click already has the item in view.
    private func scrollSelectionIntoEnclosingScrollView() {
        guard isEmbedded,
              collectionView.window?.firstResponder === collectionView,
              let path = collectionView.selectionIndexPaths.sorted().last,
              let item = collectionView.item(at: path),
              let outer = view.enclosingScrollView,
              let document = outer.documentView else { return }
        let rect = collectionView.convert(item.view.frame, to: document)
        document.scrollToVisible(rect.insetBy(dx: 0, dy: -12))
    }

    // MARK: - Context menu targets

    /// Right-clicking inside a selection acts on all of it; right-clicking outside one
    /// acts on that album alone and adopts it, so the menu and the selection agree.
    private func albumsForContextAction() -> [Album] {
        guard let clicked = collectionView.clickedIndexPath,
              albums.indices.contains(clicked.item) else { return [] }
        if collectionView.selectionIndexPaths.contains(clicked) {
            return selectedAlbums()
        }
        collectionView.selectionIndexPaths = [clicked]
        publishSelection()
        return [albums[clicked.item]]
    }

    @objc private func menuOpen() {
        guard let album = albumsForContextAction().first else { return }
        onOpen?(album)
    }
    @objc private func menuPlay() { withContextAlbums { actions.play($0) } }
    @objc private func menuShuffle() { withContextAlbums { actions.shuffle($0) } }
    @objc private func menuPlayNext() { withContextAlbums { actions.playNext($0) } }
    @objc private func menuAddToEnd() { withContextAlbums { actions.addToEnd($0) } }
    @objc private func menuAddToPlaylist() { withContextAlbums { actions.addToPlaylist($0) } }
    @objc private func menuDownload() { withContextAlbums { actions.download($0) } }
    @objc private func menuRemoveDownload() { withContextAlbums { actions.removeDownload($0) } }

    private func withContextAlbums(_ body: ([Album]) -> Void) {
        let target = albumsForContextAction()
        guard !target.isEmpty else { return }
        body(target)
    }
}

extension AlbumsGridViewController: NSCollectionViewDelegateFlowLayout {
    /// Asked per layout pass rather than cached on the layout's `itemSize`. The cached
    /// form was computed from whatever width the scroll view happened to have at the
    /// first layout — on launch that's before the window has its restored size, and
    /// nothing recomputed it afterwards. Undersized items don't just look small:
    /// NSCollectionViewFlowLayout justifies each row, so the slack turns into gaps, and
    /// the grid opens with the covers spread far apart until the window is nudged.
    func collectionView(_ collectionView: NSCollectionView,
                        layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        itemSize(forWidth: collectionView.bounds.width)
    }
}

extension AlbumsGridViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        albums.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: AlbumGridItem.identifier, for: indexPath)
        guard let cell = item as? AlbumGridItem, albums.indices.contains(indexPath.item) else { return item }
        let album = albums[indexPath.item]
        cell.accentColor = accentNSColor
        cell.isEmphasized = self.collectionView.isFirstResponderEmphasis
        cell.onPlay = { [weak self] in self?.actions.play([album]) }
        cell.isHovered = indexPath == hoveredIndexPath
        cell.configure(album: album)
        return cell
    }
}

extension AlbumsGridViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        !indexPaths.isEmpty
    }

    /// One item per album carrying its id; the sidebar expands it to tracks on drop.
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard albums.indices.contains(indexPath.item) else { return nil }
        let item = NSPasteboardItem()
        item.setString(albums[indexPath.item].id.uuidString, forType: .musicBoxAlbums)
        return item
    }

    /// Dragging an album out of the grid copies it into whatever it lands on; it never
    /// moves anything, so the grid itself is not a reorderable list.
    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .copy : []
    }

    /// Dragging an unselected album drags just that one, matching how the context menu
    /// treats a right-click outside the selection.
    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>
    ) {
        if !indexPaths.isSubset(of: collectionView.selectionIndexPaths) {
            collectionView.selectionIndexPaths = indexPaths
            publishSelection()
        }
        keepSourceItemsVisible(in: collectionView, at: indexPaths)
    }

    /// Runs before AppKit applies the hiding, which is what makes it a no-op rather
    /// than a correction.
    private func keepSourceItemsVisible(in collectionView: NSCollectionView, at indexPaths: Set<IndexPath>) {
        for path in indexPaths {
            (collectionView.item(at: path) as? AlbumGridItem)?.suppressesHiding = true
        }
    }

    /// Lift the suppression once the drag is over, so ordinary hiding works again.
    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        for item in collectionView.visibleItems() {
            (item as? AlbumGridItem)?.suppressesHiding = false
            item.view.isHidden = false
        }
    }

    /// NSCollectionView doesn't push the state onto the items itself; without this the
    /// rubber band tracks but nothing under it changes until the mouse comes up.
    func collectionView(
        _ collectionView: NSCollectionView,
        didChangeItemsAt indexPaths: Set<IndexPath>,
        to highlightState: NSCollectionViewItem.HighlightState
    ) {
        for path in indexPaths {
            (collectionView.item(at: path) as? AlbumGridItem)?.highlightState = highlightState
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        publishSelection()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        publishSelection()
    }
}

extension AlbumsGridViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let clicked = collectionView.clickedIndexPath,
              albums.indices.contains(clicked.item) else { return }
        let target = collectionView.selectionIndexPaths.contains(clicked)
            ? selectedAlbums()
            : [albums[clicked.item]]

        if target.count == 1 {
            addItem(to: menu, title: "Open", action: #selector(menuOpen))
            menu.addItem(.separator())
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
            if actions.isFullyDownloaded(target) {
                addItem(to: menu, title: "Remove Download", action: #selector(menuRemoveDownload))
            } else {
                addItem(to: menu, title: "Download", action: #selector(menuDownload))
            }
        }
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector) {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
}

/// NSCollectionView has no doubleAction the way NSTableView does, and no notion of a
/// clicked-but-unselected item for menus, so both are tracked here.
final class AlbumsCollectionView: NSCollectionView {
    var onDoubleClick: ((IndexPath) -> Void)?
    var onOpenSelection: (() -> Void)?
    var onEmphasisChange: (() -> Void)?
    var onHoverChange: ((IndexPath?) -> Void)?
    private(set) var clickedIndexPath: IndexPath?
    private var trackingArea: NSTrackingArea?

    /// Selection paints the accent only while the grid has focus, matching the tables.
    var isFirstResponderEmphasis: Bool {
        window?.firstResponder === self && (window?.isKeyWindow ?? false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverChange?(indexPathForItem(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(nil)
    }

    /// Recomputed from the pointer's current position rather than an event, for the cases
    /// that produce no mouse event at all — scrolling, and cells being recycled under it.
    func refreshHoverFromPointer() {
        guard let window, window.isKeyWindow else { onHoverChange?(nil); return }
        let inWindow = window.mouseLocationOutsideOfEventStream
        let local = convert(inWindow, from: nil)
        guard visibleRect.contains(local) else { onHoverChange?(nil); return }
        onHoverChange?(indexPathForItem(at: local))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        clickedIndexPath = indexPathForItem(at: point)
        // super selects on mouseDown, which is what makes selection feel instant; the
        // second click of a double arrives with the selection already settled.
        super.mouseDown(with: event)
        if event.clickCount == 2, let path = clickedIndexPath {
            onDoubleClick?(path)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        clickedIndexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Return opens, matching double-click. Everything else — arrows, Cmd+A,
        // shift-extend — NSCollectionView already handles.
        if event.keyCode == 36 || event.keyCode == 76 {
            onOpenSelection?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        defer { onEmphasisChange?() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { onEmphasisChange?() }
        return super.resignFirstResponder()
    }
}
#endif
