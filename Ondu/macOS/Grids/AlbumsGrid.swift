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
    /// One line in a summary row, where the height is reserved by the caller and has to
    /// be right; two in the library grid, where a long album name would otherwise lose
    /// its end.
    var titleLines: Int = 2
    /// How many cells fit across, and how tall one row is, as the grid actually laid it
    /// out. A caller that reserves the grid's height can't work this out from the width
    /// it thinks the grid has: the scroll view keeps some of that for its scroller, and
    /// being a few points out is invisible until it crosses a column breakpoint, where
    /// the reserved height is suddenly for a different cell size than the one built.
    var onMetricsChange: ((Int, CGFloat) -> Void)? = nil
    /// Embedded in a taller scrolling page rather than owning the scroll. Drops the
    /// scroller and the elastic bounce so the wheel reaches the page behind it.
    var embedded: Bool = false
    /// See TracksTable.claimsKeyboardFocus.
    var claimsKeyboardFocus: Bool = false
    /// Room for chrome floating over the top of the grid, which content scrolls under.
    var topContentInset: CGFloat = 0

    func makeNSViewController(context: Context) -> AlbumsGridViewController {
        let vc = AlbumsGridViewController()
        apply(to: vc)
        return vc
    }

    func updateNSViewController(_ vc: AlbumsGridViewController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: AlbumsGridViewController) {
        vc.titleLines = titleLines
        vc.onMetricsChange = onMetricsChange
        vc.claimsKeyboardFocus = claimsKeyboardFocus
        vc.topContentInset = topContentInset
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
    /// Measured off Music.app at 1458pt wide: ~217pt covers, ~18.5pt gaps, ~38pt
    /// margins. Ours were 160/16/20, which packed noticeably more, smaller covers into
    /// the same space. The margin stays at 20 rather than their 38 — it's shared with
    /// the detail pages, and a cover shouldn't move when you open it.
    static let minimumItemWidth: CGFloat = 190
    static let interitemSpacing = Spacing.block
    private static let lineSpacing = Spacing.page
    static let sectionInset = Spacing.page
    /// The part of a cell that isn't artwork: the gap above the caption, the title, and
    /// the artist under it.
    static func captionHeight(titleLines: Int) -> CGFloat {
        titleLines >= 2 ? 58 : 42
    }

    var onMetricsChange: ((Int, CGFloat) -> Void)?
    private var lastReportedMetrics: (columns: Int, rowHeight: CGFloat)?

    var titleLines: Int = 2 {
        didSet {
            guard titleLines != oldValue, isViewLoaded else { return }
            collectionView.reloadData()
            collectionView.collectionViewLayout?.invalidateLayout()
        }
    }

    private func reportMetrics(forWidth width: CGFloat) {
        guard let onMetricsChange else { return }
        let columns = Self.columns(forWidth: width)
        let rowHeight = itemSize(forWidth: width).height
        if let last = lastReportedMetrics,
           last.columns == columns, abs(last.rowHeight - rowHeight) < 0.5 { return }
        lastReportedMetrics = (columns, rowHeight)
        onMetricsChange(columns, rowHeight)
    }

    /// How many cells fit across, for callers that trim their data to whole rows.
    static func columns(forWidth width: CGFloat) -> Int {
        let available = width - sectionInset * 2
        guard available > 0 else { return 1 }
        return max(1, Int((available + interitemSpacing) / (minimumItemWidth + interitemSpacing)))
    }

    /// Height of a grid showing `rows` rows at this width — what an embedded caller has
    /// to reserve, since the grid can't size itself inside a page that scrolls.
    static func height(forWidth width: CGFloat, rows: Int, embedded: Bool = false,
                       titleLines: Int = 2) -> CGFloat {
        let columns = CGFloat(columns(forWidth: width))
        let available = width - sectionInset * 2
        let itemWidth = max(minimumItemWidth,
                            floor((available - interitemSpacing * (columns - 1)) / columns))
        let itemHeight = itemWidth + captionHeight(titleLines: titleLines)
        return CGFloat(rows) * itemHeight
            + CGFloat(max(0, rows - 1)) * lineSpacing
            + (embedded ? 0 : sectionInset * 2)
    }

    private var isEmbedded: Bool = false
    var topContentInset: CGFloat = 0

    /// Re-applied on every update rather than only when the flag changes: the view can
    /// load either side of the first assignment, and a scroller created before it does
    /// isn't removed by setting the flag afterwards.
    var claimsKeyboardFocus = false

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
        if isEmbedded {
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets()
        } else {
            scrollView.setTopContentInset(topContentInset)
            // Same courtesy the tables give their last row: a selected cover in the last
            // line shouldn't sit flush against the window's bottom edge.
            scrollView.addBottomContentPadding()
        }
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout
        else { return }
        let vertical = isEmbedded ? 0 : Self.sectionInset
        layout.sectionInset = NSEdgeInsets(top: vertical, left: Self.sectionInset,
                                           bottom: vertical, right: Self.sectionInset)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard claimsKeyboardFocus else { return }
        collectionView.claimKeyboardFocus()
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
        reportMetrics(forWidth: width)
    }

    /// Flow layout wants a fixed item size, so the adaptive-column arithmetic that
    /// `GridItem(.adaptive(minimum:))` did for us happens here instead.
    fileprivate func itemSize(forWidth width: CGFloat) -> NSSize {
        let available = width - Self.sectionInset * 2
        guard available > 0 else {
            return NSSize(width: Self.minimumItemWidth,
                          height: Self.minimumItemWidth + Self.captionHeight(titleLines: titleLines))
        }
        let spacing = Self.interitemSpacing
        let columns = max(1, Int((available + spacing) / (Self.minimumItemWidth + spacing)))
        let itemWidth = floor((available - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return NSSize(width: itemWidth, height: itemWidth + Self.captionHeight(titleLines: titleLines))
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
            item.isEmphasized = collectionView.usesAccentSelection
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
        cell.titleLines = titleLines
        let album = albums[indexPath.item]
        cell.accentColor = accentNSColor
        cell.isEmphasized = self.collectionView.usesAccentSelection
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
        item.setString(albums[indexPath.item].id.uuidString, forType: .onduAlbums)
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

    /// Accent while the window is key, which is what the tables do — requiring focus as
    /// well meant a restored selection sat grey until you clicked the grid, and the same
    /// selection in a table beside it was accent.
    var usesAccentSelection: Bool {
        window?.isKeyWindow ?? false
    }

    private var keyObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers.removeAll()
        onEmphasisChange?()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onEmphasisChange?() }
            })
        }
    }

    deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
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
