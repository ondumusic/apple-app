#if os(macOS)
import AppKit
import Nuke
import SwiftUI

/// One album section for sections-mode rendering. The album header is drawn as a
/// non-selectable group row above the section's tracks. `tracks` should be a slice
/// of the flat `tracks` array passed to TracksTable, in the same order — selection
/// indexes refer to that flat array.
nonisolated struct TracksTableSection: Identifiable, Equatable {
    let id: UUID  // album id; used as a stable identity when the data updates
    let album: Album
    let tracks: [Track]

    static func == (lhs: TracksTableSection, rhs: TracksTableSection) -> Bool {
        if lhs.id != rhs.id { return false }
        if lhs.tracks.count != rhs.tracks.count { return false }
        for (a, b) in zip(lhs.tracks, rhs.tracks) where a.id != b.id { return false }
        return true
    }
}

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
    /// Leading album artwork per row, as Music.app shows in its Songs list and its
    /// search results. Off by default: album and artist detail already sit under one
    /// cover, so repeating it down every row would be noise.
    var showsArtwork: Bool = false
    /// Offline, a track that isn't downloaded can't be played — `availableTracks` drops
    /// it when building a queue, silently. Dimmed here so the row says so first, the way
    /// iOS's TrackRow already does.
    var isOffline: Bool = false
    /// Sorting and column visibility, for the tables that show a header to click. Nil
    /// means the view's own order, which for Songs is album artist / album / disc /
    /// number — no column expresses that, so it can't be represented as a sort.
    var sort: TrackSort? = nil
    /// The table reports the sort the header asked for; the caller re-sorts its own
    /// array and passes it back. Sorting the copy here instead would put the table's row
    /// indices out of step with the caller's, which is the bug this file's index-space
    /// comment already records three of.
    var onSortChange: ((TrackSort?) -> Void)? = nil
    /// Where this table's hidden-column choice is remembered. Nil disables the header's
    /// column menu — embedded tables have no header to right-click.
    var columnPreferenceKey: String? = nil
    /// Whether to render the # column. Meaningful where ordering is (album detail,
    /// playlists); in a flat all-songs list the per-album numbers just repeat.
    var showTrackNumber: Bool = true
    /// The app's accent. AppKit defaults to the system accent, which is why selected
    /// rows and the now-playing marks disagreed with every SwiftUI surface.
    var accent: Color = .accentColor
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
    /// When non-nil, the table renders one group-row album header per section followed
    /// by that album's tracks. `tracks` should be the flat concatenation of every
    /// section's tracks in the same order — selection indexes and onPlay indexes refer
    /// to that flat array. Selection works natively across all albums (cmd-click /
    /// shift-range), since it's a single NSTableView.
    var sections: [TracksTableSection]? = nil
    /// The caller reserves exactly this table's content height, so the room kept under
    /// the last row would be height the caller doesn't know about — enough to make the
    /// table scroll inside itself. Only search does this; a detail page owns its scroll
    /// and wants the room, or a selected last row sits flush against the window edge.
    var fitsContentHeight: Bool = false
    /// Whether this is the section's primary list, and so should take keyboard focus
    /// from the sidebar. Off for a list that shares a page with one — an artist's tracks
    /// beside the artist list — where whichever mounted first would otherwise win.
    var claimsKeyboardFocus: Bool = false
    /// Reports the table's laid-out content height. An embedded caller has to reserve
    /// the height itself, and rows × rowHeight isn't it — the inset style pads the top
    /// and bottom, which left the last of a fixed-height list scrollable inside itself.
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    /// Flat track index → text of a divider row inserted above it. Album detail uses it
    /// for "Disc 1"/"Disc 2"; a multi-disc album otherwise restarts at track 1 with
    /// nothing to say why.
    var groupLabels: [Int: String] = [:]
    /// Caller-supplied SwiftUI view used to render an album header row. The view is
    /// hosted via NSHostingView. Only consulted when `sections` is set.
    var sectionHeader: ((Album) -> AnyView)? = nil
    /// Pull the section header back out of NSTableView's cell inset, so its content
    /// lines up with the page around the table rather than with the track rows inside
    /// it. Album detail wants this — its header is the page's header, and its artwork
    /// has to sit where the same cover sat in the grid. The artist page does not: its
    /// section headers align with the track titles beneath them on purpose.
    var sectionHeaderIgnoresCellInset: Bool = false
    /// Pixel height of section header rows. Tall enough to fit artwork + title + actions.
    var sectionHeaderHeight: CGFloat = 80
    /// Caller-supplied SwiftUI view used to render the album artwork as an overlay on
    /// the left edge of the table — spans from the section's header row down through
    /// the first few track rows (iTunes-style split layout). Sized to `artworkSize` ×
    /// `artworkSize`. When nil, no overlay is drawn.
    var artwork: ((Album) -> AnyView)? = nil
    /// Pixel size of the square artwork overlay (also drives the leftmost spacer column
    /// width = artworkSize + 2 × artworkInset).
    var artworkSize: CGFloat = 120
    /// Horizontal padding from the table's left edge to the artwork's left edge.
    var artworkInset: CGFloat = 20

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
        vc.sectionHeaderHeight = sectionHeaderHeight
        vc.sectionHeaderIgnoresCellInset = sectionHeaderIgnoresCellInset
        vc.sectionHeaderBuilder = sectionHeader
        // After the header builder, not before: changing the accent rebuilds the hosted
        // headers, and it has to rebuild them from the closure that carries the new one.
        vc.accentNSColor = NSColor(accent)
        vc.artworkBuilder = artwork
        vc.artworkSize = artworkSize
        vc.artworkInset = artworkInset
        vc.groupLabels = groupLabels
        vc.showsArtwork = showsArtwork
        vc.isOffline = isOffline
        vc.setSortable(onSortChange != nil)
        vc.onSortChange = onSortChange
        vc.columnPreferenceKey = columnPreferenceKey
        vc.applySort(sort)
        vc.onContentHeightChange = onContentHeightChange
        vc.fitsContentHeight = fitsContentHeight
        vc.claimsKeyboardFocus = claimsKeyboardFocus
        vc.update(
            tracks: tracks,
            sections: sections,
            externalSelection: selection,
            showArtist: showArtist,
            showAlbum: showAlbum,
            showTrackNumber: showTrackNumber,
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

    /// What's rendered at each NSTableView row. `.header` is a non-selectable group row
    /// that hosts a SwiftUI album header; `.track(flatIndex)` references the position in
    /// the flat `tracks` array (the source of truth for selection / onPlay indices).
    fileprivate enum DisplayRow {
        case header(Album)
        case label(String)
        case track(flatIndex: Int)
    }
    fileprivate private(set) var displayRows: [DisplayRow] = []
    /// Reverse lookup: flat track index → row in displayRows. Built alongside displayRows.
    private var rowForTrackIndex: [Int: Int] = [:]
    private var sections: [TracksTableSection]? = nil
    var sectionHeaderBuilder: ((Album) -> AnyView)?
    /// Column width = the gap the selection pill needs on its left, the artwork, and
    /// the gap to the title.
    static let artworkSize: CGFloat = 36
    static let artworkLeadingGap: CGFloat = 6
    private static let artworkTrailingGap: CGFloat = 10
    static var artworkColumnWidth: CGFloat { artworkLeadingGap + artworkSize + artworkTrailingGap }

    var showsArtwork: Bool = false {
        didSet {
            guard showsArtwork != oldValue, isViewLoaded else { return }
            applyColumnVisibility()
            tableView.reloadData()
        }
    }
    var isOffline = false {
        didSet {
            guard isOffline != oldValue, isViewLoaded else { return }
            tableView.reloadData()
        }
    }
    var onSortChange: ((TrackSort?) -> Void)?
    var columnPreferenceKey: String? {
        didSet {
            guard columnPreferenceKey != oldValue else { return }
            userHiddenColumns = Self.loadHiddenColumns(key: columnPreferenceKey)
            applyColumnVisibility()
            rebuildHeaderMenu()
        }
    }

    /// Columns the user turned off, as opposed to ones this table never offers. Kept
    /// apart because `update` re-applies the caller's choices on every pass and would
    /// otherwise put a hidden column straight back.
    private var userHiddenColumns: Set<String> = TracksTableViewController.defaultHiddenColumns
    private var activeSort: TrackSort?
    private var suppressSortCallback = false
    private var offersTrackNumber = true
    private var offersArtist = true
    private var offersAlbum = false

    /// A header only gets its click-to-sort arrow where a caller is listening for the
    /// result. Without this the tables that don't sort still drew the arrow and then
    /// ignored it.
    func setSortable(_ sortable: Bool) {
        _ = view
        for column in tableView.tableColumns {
            guard let sortColumn = TrackSortColumn(rawValue: column.identifier.rawValue) else { continue }
            column.sortDescriptorPrototype = sortable
                ? NSSortDescriptor(key: sortColumn.rawValue, ascending: true)
                : nil
        }
    }

    func applySort(_ sort: TrackSort?) {
        guard activeSort != sort else { return }
        activeSort = sort
        guard isViewLoaded else { return }
        applySortIndicator()
        rebuildHeaderMenu()
    }

    private func applySortIndicator() {
        let wanted: [NSSortDescriptor] = activeSort.map {
            [NSSortDescriptor(key: $0.column.rawValue, ascending: $0.ascending)]
        } ?? []
        guard tableView.sortDescriptors != wanted else { return }
        suppressSortCallback = true
        tableView.sortDescriptors = wanted
        suppressSortCallback = false
    }

    private static func hiddenColumnsDefaultsKey(_ key: String) -> String {
        "tracksTable.\(key).hiddenColumns"
    }

    /// Columns that exist but aren't worth the width until someone asks for them.
    private static let defaultHiddenColumns: Set<String> = ["disc", "year"]

    private static func loadHiddenColumns(key: String?) -> Set<String> {
        guard let key,
              let stored = UserDefaults.standard.stringArray(forKey: hiddenColumnsDefaultsKey(key))
        else { return defaultHiddenColumns }
        return Set(stored)
    }

    private func persistHiddenColumns() {
        guard let columnPreferenceKey else { return }
        UserDefaults.standard.set(userHiddenColumns.sorted(),
                                  forKey: Self.hiddenColumnsDefaultsKey(columnPreferenceKey))
    }

    /// Whether this table offers the column at all, before the user's choice.
    private func callerOffers(_ column: NSTableColumn) -> Bool {
        switch column.identifier.rawValue {
        case "number": return offersTrackNumber
        case "artist": return offersArtist && !isEmbedded
        case "album": return offersAlbum
        default: return true
        }
    }

    func applyColumnVisibility() {
        // Only a table with a header menu can offer these, so only it can show them —
        // otherwise every embedded table got them with no way to turn them off, since
        // the hidden set is only loaded when a preference key arrives.
        let customisable = columnPreferenceKey != nil
        discColumn.isHidden = !customisable || userHiddenColumns.contains("disc")
        yearColumn.isHidden = !customisable || userHiddenColumns.contains("year")
        numberColumn.isHidden = !callerOffers(numberColumn) || userHiddenColumns.contains("number")
        artistColumn.isHidden = !callerOffers(artistColumn) || userHiddenColumns.contains("artist")
        albumColumn.isHidden = !callerOffers(albumColumn) || userHiddenColumns.contains("album")
        durationColumn.isHidden = userHiddenColumns.contains("duration")
        artworkColumn.isHidden = !showsArtwork
        view.needsLayout = true
    }

    /// Right-click a column header to choose which columns show — the standard Mac
    /// idiom, and what Music.app does. Title is never offered: a row of durations with
    /// nothing naming them isn't a track list.
    func rebuildHeaderMenu() {
        guard isViewLoaded, let header = tableView.headerView else { return }
        guard columnPreferenceKey != nil else {
            header.menu = nil
            return
        }
        let menu = NSMenu()
        for column in [numberColumn, discColumn, artistColumn, albumColumn, yearColumn, durationColumn]
        where callerOffers(column) {
            let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.identifier.rawValue
            item.state = userHiddenColumns.contains(column.identifier.rawValue) ? .off : .on
            menu.addItem(item)
        }
        guard !menu.items.isEmpty else {
            header.menu = nil
            return
        }
        menu.addItem(.separator())
        // The way back to the view's own order, which no column can express.
        let reset = NSMenuItem(title: NSLocalizedString("Default Order", comment: ""),
                               action: #selector(resetSort), keyEquivalent: "")
        reset.target = self
        reset.state = activeSort == nil ? .on : .off
        menu.addItem(reset)
        header.menu = menu
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if userHiddenColumns.contains(id) {
            userHiddenColumns.remove(id)
        } else {
            userHiddenColumns.insert(id)
        }
        persistHiddenColumns()
        applyColumnVisibility()
        rebuildHeaderMenu()
    }

    @objc private func resetSort() {
        activeSort = nil
        applySortIndicator()
        onSortChange?(nil)
        rebuildHeaderMenu()
    }

    var groupLabels: [Int: String] = [:] {
        didSet { if groupLabels != oldValue { rebuildDisplayRows(); tableView.reloadData() } }
    }
    private static let labelRowHeight: CGFloat = 30
    var sectionHeaderHeight: CGFloat = 80
    var sectionHeaderIgnoresCellInset = false
    /// NSTableView's own cell inset, measured in viewDidLayout. Section headers that opt
    /// out of it are shifted back by this much.
    private var cellInset: CGFloat = 16
    /// Presence — not identity — decides whether the artwork gutter exists, and that
    /// flip has to reach the columns even when the tracks themselves didn't change.
    var artworkBuilder: ((Album) -> AnyView)? {
        didSet {
            guard isViewLoaded, (oldValue == nil) != (artworkBuilder == nil) else { return }
            applySectionsColumns()
            rebuildArtworkOverlays()
            tableView.reloadData()
        }
    }
    var artworkSize: CGFloat = 120
    var artworkInset: CGFloat = 20
    /// One NSHostingView per album, keyed by album id. Subviews of `tableView` so they
    /// scroll with the document; positioned in `viewDidLayout` to anchor at each
    /// section's header row.
    private var artworkOverlays: [UUID: NSHostingView<AnyView>] = [:]
    /// Width reserved on the left for the artwork overlay in sections mode (= artworkSize
    /// + 2 × artworkInset). Track row content starts here; the selection pill draws
    /// from here too. Computed from artworkSize/artworkInset on each layout.
    private var sectionsLeftInset: CGFloat = 0

    private let spacerColumn = NSTableColumn(identifier: .init("sectionSpacer"))
    private let artworkColumn = NSTableColumn(identifier: .init("artwork"))
    private let numberColumn = NSTableColumn(identifier: .init("number"))
    private let discColumn = NSTableColumn(identifier: .init("disc"))
    private let yearColumn = NSTableColumn(identifier: .init("year"))
    private let titleColumn  = NSTableColumn(identifier: .init("title"))
    private let artistColumn = NSTableColumn(identifier: .init("artist"))
    private let albumColumn  = NSTableColumn(identifier: .init("album"))
    private let durationColumn = NSTableColumn(identifier: .init("duration"))

    private var suppressSelectionCallback = false
    var onContentHeightChange: ((CGFloat) -> Void)?
    var claimsKeyboardFocus = false
    var fitsContentHeight = false {
        didSet {
            guard fitsContentHeight != oldValue, isViewLoaded else { return }
            applyBottomContentPadding()
        }
    }

    private func applyBottomContentPadding() {
        if fitsContentHeight {
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets()
        } else {
            scrollView.addBottomContentPadding()
        }
    }

    private var lastReportedContentHeight: CGFloat = 0
    private var hoveredRow: Int?
    private var trackingArea: NSTrackingArea?

    override func viewDidAppear() {
        super.viewDidAppear()
        guard claimsKeyboardFocus else { return }
        tableView.claimKeyboardFocus()
    }

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
        tableView.onNumberColumnClick = { [weak self] row in self?.playRow(row) }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onEnter = { [weak self] in self?.handleEnter() }

        let artworkWidth = Self.artworkColumnWidth
        configureColumn(artworkColumn,  title: "",         width: artworkWidth, alignment: .left, resizable: false)
        artworkColumn.minWidth = artworkWidth
        artworkColumn.maxWidth = artworkWidth
        artworkColumn.isHidden = !showsArtwork
        configureColumn(numberColumn,   title: "#",        width: 36,  alignment: .right,  resizable: false)
        configureColumn(titleColumn,    title: "Title",    width: 280, alignment: .left,   resizable: true)
        configureColumn(artistColumn,   title: "Artist",   width: 180, alignment: .left,   resizable: true)
        configureColumn(albumColumn,    title: "Album",    width: 180, alignment: .left,   resizable: true)
        configureColumn(durationColumn, title: "Duration", width: 70,  alignment: .right,  resizable: false)
        // Off unless asked for, via the header's menu. Useful when they matter — a
        // multi-disc set, or sorting a library by year — and noise the rest of the time.
        configureColumn(discColumn,     title: "Disc",     width: 44,  alignment: .right,  resizable: false)
        configureColumn(yearColumn,     title: "Year",     width: 54,  alignment: .right,  resizable: false)

        for column in [artworkColumn, numberColumn, discColumn, titleColumn, artistColumn,
                       albumColumn, yearColumn, durationColumn] {
            tableView.addTableColumn(column)
        }

        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        // Scrolling slides rows under a stationary cursor without producing a mouse
        // event, so hover has to be re-derived from the pointer as well as from events.
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHoverFromPointer() }
        }

        // Drag source: tracks can be dropped onto sidebar playlist rows (.copy externally)
        // or reordered within this same table (.move locally).
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        // Self-drop target so we can intercept reorder drags.
        tableView.registerForDraggedTypes([.musicBoxTracks])
        // Show a gap-line indicator at the insertion point so users know reorder drops
        // happen between rows, not onto them.
        tableView.draggingDestinationFeedbackStyle = .gap

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
        scrollView.addBottomContentPadding()
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
        if let trackingArea { view.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        view.addTrackingArea(area)
        trackingArea = area
        if let onContentHeightChange {
            let height = tableView.frame.height
            if height > 0, abs(height - lastReportedContentHeight) > 0.5 {
                lastReportedContentHeight = height
                onContentHeightChange(height)
            }
        }
        guard isEmbedded else { return }
        // .sourceList highlight inserts NSVisualEffectViews into the row hierarchy for
        // the rounded selection backdrop. We want the rounded pill but not the blur —
        // hide the effect views so the parent's solid background shows through.
        suppressEmbeddedVibrancy(in: scrollView)
        updateArtworkOverlayPositions()
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
        // Measure from a track row — header rows span all columns and would report 0.
        let detectedInset: CGFloat = {
            for row in 0..<tableView.numberOfRows where flatTrackIndex(forRow: row) != nil {
                // In sections mode the spacer column shifts cell origins by sectionsLeftInset;
                // subtract it so we get the inset NSTableView itself adds.
                return tableView.frameOfCell(atColumn: tableView.column(withIdentifier: numberColumn.identifier),
                                              row: row).minX - sectionsLeftInset
            }
            return 16
        }()
        if abs(cellInset - detectedInset) > 0.5 {
            cellInset = detectedInset
            for row in 0..<tableView.numberOfRows where isHeaderRow(row) {
                (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SectionHeaderCell)?
                    .horizontalOutset = sectionHeaderIgnoresCellInset ? detectedInset : 0
            }
        }
        // Title absorbs the remainder after the locked-width columns and the source-list
        // insets (and the spacer column when in sections mode).
        let artworkWidth: CGFloat = artworkColumn.isHidden ? 0 : Self.artworkColumnWidth
        let numberWidth: CGFloat = numberColumn.isHidden ? 0 : 36
        let durationWidth: CGFloat = 70
        var remaining: CGFloat = target - sectionsLeftInset
        remaining -= artworkWidth
        remaining -= numberWidth
        remaining -= discColumn.isHidden ? 0 : 44
        remaining -= yearColumn.isHidden ? 0 : 54
        remaining -= durationWidth
        remaining -= 2 * detectedInset
        let titleWidth = max(120, remaining)
        if abs(titleColumn.width - titleWidth) > 0.5 {
            titleColumn.width = titleWidth
        }
        if abs(tableView.frame.width - target) > 0.5 {
            tableView.setFrameSize(NSSize(width: target, height: tableView.frame.height))
        }
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

    /// Repaints on change: rows and cells cache the colour when they're configured, so
    /// switching accent in Settings would otherwise only show up on the next reload.
    var accentNSColor: NSColor = .controlAccentColor {
        didSet {
            guard accentNSColor != oldValue, isViewLoaded else { return }
            tableView.enumerateAvailableRowViews { rowView, row in
                (rowView as? AccentSelectionRowView)?.selectionColor = accentNSColor
                for column in 0..<rowView.numberOfColumns {
                    switch rowView.view(atColumn: column) {
                    case let cell as TitleCell: cell.accentColor = accentNSColor
                    case let cell as NumberOrSpeakerCell: cell.accentColor = accentNSColor
                    default: break
                    }
                }
                // A section header is hosted SwiftUI built by a closure that captured
                // the accent when the row was last hosted, so repainting the cell isn't
                // enough — it has to be built again.
                if displayRows.indices.contains(row),
                   case .header(let album) = displayRows[row],
                   let builder = sectionHeaderBuilder,
                   let cell = rowView.view(atColumn: 0) as? SectionHeaderCell {
                    cell.host(view: builder(album))
                }
                rowView.needsDisplay = true
            }
        }
    }
    private(set) var isEmbedded: Bool = false
    /// nil until the first style pass. Without it the equality guard below skips
    /// configuration for a standalone table, since `embedded` and `isEmbedded` are both
    /// false to begin with — which left the scroll view transparent over the window's
    /// material, so its labels were vibrancy-blended and greyed out whenever the window
    /// wasn't key.
    private var appliedEmbeddedStyle: Bool?

    func applyEmbeddedStyle(_ embedded: Bool) {
        // makeNSViewController calls these before SwiftUI requests `view`, which is
        // when loadView runs and sets the standalone defaults. Force the load now so
        // our embedded overrides win.
        _ = view
        guard appliedEmbeddedStyle != embedded else { return }
        appliedEmbeddedStyle = embedded
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
            // .none so AccentSelectionRowView's accent pill paints; NSTableView draws both
            // .regular and .sourceList selection itself and never delegates to a row
            // view's drawSelection, so either would cover the pill with the system
            // accent. Also suppress the focus ring AppKit paints around a right-clicked
            // row — it ignores our row-level draw overrides and would span the artwork.
            tableView.selectionHighlightStyle = .none
            tableView.focusRingType = .none
            scrollView.focusRingType = .none
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
            // Rows butt up against each other and the hairline separates them, as in the
            // queue table. AppKit's default 2pt gap also made the table 2pt per row taller
            // than rows × rowHeight, which is the only height an embedded caller can
            // reserve — the search page's list scrolled inside itself because of it.
            tableView.intercellSpacing = .zero
            // Don't pin album-header group rows to the top during scroll — Apple Music's
            // artist page lets them scroll away naturally.
            tableView.floatsGroupRows = false
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
            applyBottomContentPadding()
            scrollView.borderType = .noBorder
            scrollView.contentView.drawsBackground = false
            scrollView.contentView.backgroundColor = .clear
        } else {
            tableView.usesAlternatingRowBackgroundColors = true
            tableView.style = .inset
            tableView.intercellSpacing = NSSize(width: 3, height: 2)
            tableView.backgroundColor = .controlBackgroundColor
            // .none so our own pill paints; .regular would draw the system accent over it.
            tableView.selectionHighlightStyle = .none
            tableView.focusRingType = .default
            scrollView.focusRingType = .default
            scrollView.drawsBackground = true
            scrollView.hasVerticalScroller = true
            scrollView.verticalScrollElasticity = .automatic
        }       
        tableView.reloadData()
    }

    func update(
        tracks newTracks: [Track],
        sections newSections: [TracksTableSection]?,
        externalSelection: Set<UUID>,
        showArtist: Bool,
        showAlbum: Bool,
        showTrackNumber: Bool,
        currentlyPlayingTrackId newCurrent: UUID?,
        isPlaying newIsPlaying: Bool,
        usesPlaylistPosition newUsesPlaylistPosition: Bool
    ) {
        self.usesPlaylistPosition = newUsesPlaylistPosition
        self.embeddedShowsArtist = showArtist
        // Artist column is always hidden in embedded mode — the title cell stacks the
        // artist beneath the title when needed.
        offersArtist = showArtist
        offersAlbum = showAlbum
        offersTrackNumber = showTrackNumber
        applyColumnVisibility()
        rebuildHeaderMenu()

        let changed = !tracksMatch(self.tracks, newTracks) || !sectionsMatch(self.sections, newSections)
        // Detect rows whose `isDownloaded` flipped without otherwise changing — we want
        // to refresh those cells (the downloaded indicator) without triggering a full
        // reloadData (which would reset the whole table mid-interaction).
        var downloadStateChangedRows = IndexSet()
        if !changed {
            for (idx, (oldTrack, newTrack)) in zip(self.tracks, newTracks).enumerated()
            where oldTrack.isDownloaded != newTrack.isDownloaded {
                if let row = rowForTrackIndex[idx] {
                    downloadStateChangedRows.insert(row)
                }
            }
        }
        let previousCurrent = self.currentlyPlayingTrackId
        let previousPlaying = self.isPlaying
        self.tracks = newTracks
        self.sections = newSections
        self.currentlyPlayingTrackId = newCurrent
        self.isPlaying = newIsPlaying

        if changed {
            rebuildDisplayRows()
            tableView.reloadData()
            // New sections get their overlay views built at the origin, and a row-set
            // change on its own doesn't dirty the view's layout — so without this the
            // artwork for every album that reappeared stacked up in the top-left.
            updateArtworkOverlayPositions()
        } else {
            // Same row set — refresh just the cells that need it.
            var rows = downloadStateChangedRows
            if previousCurrent != newCurrent || previousPlaying != newIsPlaying {
                if let prev = previousCurrent,
                   let trackIdx = tracks.firstIndex(where: { $0.id == prev }),
                   let row = rowForTrackIndex[trackIdx] {
                    rows.insert(row)
                }
                if let cur = newCurrent,
                   let trackIdx = tracks.firstIndex(where: { $0.id == cur }),
                   let row = rowForTrackIndex[trackIdx] {
                    rows.insert(row)
                }
            }
            if !rows.isEmpty {
                // Reload all column indexes for the affected rows — title column carries
                // the downloaded indicator, number column carries the play indicator.
                let allColumns = IndexSet(0..<tableView.numberOfColumns)
                tableView.reloadData(forRowIndexes: rows, columnIndexes: allColumns)
            }
        }
        applyExternalSelection(externalSelection)
    }

    private func rebuildDisplayRows() {
        var rows: [DisplayRow] = []
        var rowForTrack: [Int: Int] = [:]
        if let sections = self.sections {
            // Use sections to interleave headers with their tracks. Track flat-index is
            // walked across sections in order; sections must reflect the same flat order
            // as `self.tracks`.
            var flatIdx = 0
            for section in sections {
                rows.append(.header(section.album))
                for _ in section.tracks {
                    if let label = groupLabels[flatIdx] { rows.append(.label(label)) }
                    rowForTrack[flatIdx] = rows.count
                    rows.append(.track(flatIndex: flatIdx))
                    flatIdx += 1
                }
            }
        } else {
            for (idx, _) in tracks.enumerated() {
                if let label = groupLabels[idx] { rows.append(.label(label)) }
                rowForTrack[idx] = rows.count
                rows.append(.track(flatIndex: idx))
            }
        }
        self.displayRows = rows
        self.rowForTrackIndex = rowForTrack
        applySectionsColumns()
        rebuildArtworkOverlays()
    }

    /// Adds (or removes) the leftmost spacer column based on whether we're in sections
    /// mode, which is only when there's an artwork overlay to reserve room for. The
    /// selection style itself is owned by applyEmbeddedStyle — it's `.none` either way
    /// so AccentSelectionRowView's accent pill is the only thing painting selection.
    private func applySectionsColumns() {
        // Explicitly unanimated: adding or removing the spacer column runs inside
        // whatever animation context is open when SwiftUI updates the representable, so
        // crossing the compact breakpoint slid every track across to its new indent
        // while the artwork it was making room for appeared instantly. A SwiftUI
        // .animation(nil:) can't reach in here to stop it.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        defer { NSAnimationContext.endGrouping() }

        let needsSpacer = sections != nil && artworkBuilder != nil
        sectionsLeftInset = needsSpacer ? (artworkSize + 2 * artworkInset) : 0
        if needsSpacer {
            spacerColumn.title = ""
            spacerColumn.minWidth = sectionsLeftInset
            spacerColumn.maxWidth = sectionsLeftInset
            spacerColumn.width = sectionsLeftInset
            spacerColumn.resizingMask = []
            if !tableView.tableColumns.contains(spacerColumn) {
                tableView.addTableColumn(spacerColumn)
            }
            if let idx = tableView.tableColumns.firstIndex(of: spacerColumn), idx != 0 {
                tableView.moveColumn(idx, toColumn: 0)
            }
        } else if tableView.tableColumns.contains(spacerColumn) {
            tableView.removeTableColumn(spacerColumn)
        }
    }

    /// Creates / updates / removes one NSHostingView per album for the artwork overlay.
    /// Positioning happens in viewDidLayout once row frames are known.
    private func rebuildArtworkOverlays() {
        let activeIds = artworkBuilder == nil ? [] : Set(sections?.map(\.id) ?? [])
        for (id, view) in artworkOverlays where !activeIds.contains(id) {
            view.removeFromSuperview()
            artworkOverlays.removeValue(forKey: id)
        }
        guard let sections = sections, let builder = artworkBuilder else { return }
        for section in sections {
            if let existing = artworkOverlays[section.id] {
                existing.rootView = builder(section.album)
            } else {
                let host = NSHostingView(rootView: builder(section.album))
                host.translatesAutoresizingMaskIntoConstraints = true
                tableView.addSubview(host)
                artworkOverlays[section.id] = host
            }
        }
    }

    /// Anchors each artwork overlay to its section's header-row position. Brings overlays
    /// to the front of tableView's subviews so reused row views (added during scroll)
    /// don't draw on top of them.
    private func updateArtworkOverlayPositions() {
        guard sections != nil, !artworkOverlays.isEmpty else { return }
        // Read the header rows out of displayRows rather than counting section lengths:
        // group-label rows sit between tracks and would throw the arithmetic off.
        for (rowIdx, row) in displayRows.enumerated() {
            guard case .header(let album) = row, let view = artworkOverlays[album.id] else { continue }
            let headerFrame = tableView.rect(ofRow: rowIdx)
            // Width = artworkSize (artwork itself); the SwiftUI overlay can render
            // a caption below it, so reserve a bit of vertical space for that too.
            view.frame = NSRect(
                x: artworkInset,
                y: headerFrame.minY + artworkInset,
                width: artworkSize,
                height: artworkSize + 40
            )
        }
        for (_, view) in artworkOverlays {
            tableView.addSubview(view, positioned: .above, relativeTo: nil)
        }
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

    private func sectionsMatch(_ a: [TracksTableSection]?, _ b: [TracksTableSection]?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let lhs?, let rhs?):
            guard lhs.count == rhs.count else { return false }
            return zip(lhs, rhs).allSatisfy { $0 == $1 }
        default: return false
        }
    }

    /// Maps a tableView row to its flat track index, or nil if the row is a section header.
    fileprivate func flatTrackIndex(forRow row: Int) -> Int? {
        guard displayRows.indices.contains(row) else { return nil }
        if case .track(let idx) = displayRows[row] { return idx }
        return nil
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
        let indices = IndexSet(tracks.enumerated().compactMap { (idx, track) -> Int? in
            guard ids.contains(track.id), let row = rowForTrackIndex[idx] else { return nil }
            return row
        })
        if indices == tableView.selectedRowIndexes { return }
        suppressSelectionCallback = true
        tableView.selectRowIndexes(indices, byExtendingSelection: false)
        suppressSelectionCallback = false
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        applyHover(row: tableView.row(at: tableView.convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        applyHover(row: -1)
    }

    private func refreshHoverFromPointer() {
        guard let window = view.window, window.isKeyWindow else { return applyHover(row: -1) }
        let local = tableView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard tableView.visibleRect.contains(local) else { return applyHover(row: -1) }
        applyHover(row: tableView.row(at: local))
    }

    private func applyHover(row: Int) {
        let target = flatTrackIndex(forRow: row) == nil ? nil : row
        guard target != hoveredRow else { return }
        hoveredRow = target
        let column = tableView.column(withIdentifier: numberColumn.identifier)
        guard column >= 0 else { return }
        for visible in 0..<tableView.numberOfRows {
            guard let cell = tableView.view(atColumn: column, row: visible, makeIfNecessary: false)
                    as? NumberOrSpeakerCell else { continue }
            cell.isHovered = (visible == target)
        }
    }

    fileprivate func playRow(_ row: Int) {
        guard let trackIdx = flatTrackIndex(forRow: row) else { return }
        onPlay?(trackIdx)
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard let trackIdx = flatTrackIndex(forRow: row) else { return }
        let track = tracks[trackIdx]

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
        onPlay?(trackIdx)
    }

    private func handleEnter() {
        // Enter on a single selection plays that row; on multi-selection, plays the
        // earliest selected row (same semantic as iTunes / Apple Music).
        for row in tableView.selectedRowIndexes {
            if let idx = flatTrackIndex(forRow: row) {
                onPlay?(idx)
                return
            }
        }
    }
}

// MARK: - Key-aware table

private final class KeyAwareTableView: NSTableView {
    var onEnter: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Click in the # column, where the hover glyph promises a play button.
    var onNumberColumnClick: ((Int) -> Void)?
    /// Right-clicked row recorded by our own rightMouseDown override (which bypasses
    /// NSTableView's default handler to suppress its full-row outline highlight).
    /// `clickedRow` returns this when set, otherwise falls through to super.
    private var manualClickedRow: Int = -1

    override var clickedRow: Int {
        manualClickedRow != -1 ? manualClickedRow : super.clickedRow
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clicked = column(at: point)
        if event.clickCount == 1, clicked >= 0,
           tableColumns[clicked].identifier.rawValue == "number",
           row(at: point) >= 0 {
            onNumberColumnClick?(row(at: point))
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        // NSTableView's default rightMouseDown draws a full-row "menu target" outline
        // on the right-clicked row that ignores our custom-pill bounds. Bypass it —
        // record the clicked row ourselves and pop the contextual menu directly.
        let point = convert(event.locationInWindow, from: nil)
        manualClickedRow = self.row(at: point)
        defer { manualClickedRow = -1 }
        if let menu = self.menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

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
        displayRows.count
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        for row in rowIndexes {
            (tableView.rowView(atRow: row, makeIfNecessary: false) as? AccentSelectionRowView)?
                .suppressesHiding = true
        }
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? AccentSelectionRowView)?.suppressesHiding = false
            rowView.isHidden = false
        }
    }

    /// Without this AppKit has nothing to match a keystroke against and beeps — which is
    /// what you get after clicking a track in the artist split, where focus moves off the
    /// artist list onto this table.
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard let index = flatTrackIndex(forRow: row) else { return nil }
        return tracks[index].name
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        // Only track rows are draggable; section headers are not.
        guard let trackIdx = flatTrackIndex(forRow: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(tracks[trackIdx].id.uuidString, forType: .musicBoxTracks)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Reorder is disabled in sections mode — meaning would be ambiguous when dropping
        // between or onto section headers.
        guard onReorder != nil,
              sections == nil,
              info.draggingSource as? NSTableView === self.tableView
        else { return [] }
        // Force the operation to .above so dropping anywhere (even directly on a row)
        // becomes "insert between rows" instead of "drop onto row" (which we don't
        // support and would silently fail).
        if dropOperation != .above {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation dropOperation: NSTableView.DropOperation) -> Bool {
        guard let onReorder,
              sections == nil,
              info.draggingSource as? NSTableView === self.tableView
        else { return false }
        // Dragged rows aren't necessarily in selectedRowIndexes — NSTableView lets you
        // click-and-drag an unselected row directly. Read the dragged track ids out of
        // the pasteboard items we wrote in pasteboardWriterForRow and resolve them
        // back to row indices in the current `tracks` array.
        let draggedTrackIds: [UUID] = info.draggingPasteboard.pasteboardItems?.compactMap { item in
            item.string(forType: .musicBoxTracks).flatMap(UUID.init)
        } ?? []
        let draggedRows = IndexSet(draggedTrackIds.compactMap { id in
            tracks.firstIndex(where: { $0.id == id })
        })
        guard !draggedRows.isEmpty else { return false }
        onReorder(draggedRows, row)
        return true
    }
}

// MARK: - Delegate

extension TracksTableViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard displayRows.indices.contains(row) else { return false }
        if case .header = displayRows[row] { return true }
        if case .label = displayRows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Section headers aren't selectable — only tracks.
        flatTrackIndex(forRow: row) != nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard displayRows.indices.contains(row) else { return tableView.rowHeight }
        if case .header = displayRows[row] { return sectionHeaderHeight }
        if case .label = displayRows[row] { return Self.labelRowHeight }
        return tableView.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // In embedded mode, NSTableRowView's default drawBackground paints a backdrop
        // even when tableView.backgroundColor is .clear — that's the residual grey we
        // were seeing. Custom row view no-ops the draw so the parent shows through and
        // also paints the inter-row hairline divider.
        let view = AccentSelectionRowView()
        view.selectionColor = accentNSColor
        guard isEmbedded else {
            // Standalone: no hairline — alternating row colours already separate the rows
            // there. The pill matches the 10pt margin `style = .inset` gives the stripes,
            // so it doesn't run into the sidebar divider.
            view.customSelectionLeftInset = 10
            view.customSelectionRightInset = 10
            view.suppressDivider = true
            view.drawsRowBackground = true
            return view
        }
        let isHeader = isHeaderRow(row)
        let nextIsHeader = isHeaderRow(row + 1)
        // Suppress dividers around section headers and after the last row of the table.
        view.suppressDivider = isHeader || nextIsHeader || row == displayRows.count - 1
        // In sections mode, draw selection pill from where track cells actually begin —
        // that's spacer column width + NSTableView's own ~16pt cell-area inset. Without
        // the +16, the pill extends 16pt back into the artwork zone.
        if sectionsLeftInset > 0 {
            view.customSelectionLeftInset = sectionsLeftInset + 16
            // The trailing side needs the same clearance the other branches give it;
            // left at its default the pill ran flush to the window edge.
            view.customSelectionRightInset = 12
        } else {
            // No artwork gutter to clear, but still inset — full-bleed ran the pill
            // straight into the sidebar divider. 12 clears the edge without reaching the
            // track number, which sits further in.
            view.customSelectionLeftInset = 12
            view.customSelectionRightInset = 12
        }
        if showsArtwork {
            // The pill has to start outside the artwork — inset the usual 12 and the
            // cover hangs off its left edge — and end outside the duration, which the
            // usual trailing inset clipped.
            view.customSelectionLeftInset = 0
            view.customSelectionRightInset = 4
            view.dividerLeadingInset = Self.artworkColumnWidth
        }
        return view
    }

    private func isHeaderRow(_ row: Int) -> Bool {
        guard displayRows.indices.contains(row) else { return false }
        if case .header = displayRows[row] { return true }
        if case .label = displayRows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayRows.indices.contains(row) else { return nil }
        // Section header: NSTableView calls viewFor with tableColumn=nil for group
        // rows (when isGroupRow returns true). Return our hosting cell which spans the
        // full row width.
        if case .header(let album) = displayRows[row] {
            let cellId = NSUserInterfaceItemIdentifier("trackSectionHeader")
            let cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? SectionHeaderCell
                ?? SectionHeaderCell(identifier: cellId)
            cell.horizontalOutset = sectionHeaderIgnoresCellInset ? cellInset : 0
            if let builder = sectionHeaderBuilder {
                cell.host(view: builder(album))
            }
            return cell
        }
        if case .label(let text) = displayRows[row] {
            let cellId = NSUserInterfaceItemIdentifier("trackGroupLabel")
            let cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? GroupLabelCell
                ?? GroupLabelCell(identifier: cellId)
            cell.text = text
            let titleColumn = tableView.column(withIdentifier: self.titleColumn.identifier)
            if titleColumn >= 0 {
                // -2: the title cell's text starts a couple of points inside its frame.
                cell.leadingInset = tableView.frameOfCell(atColumn: titleColumn, row: row).minX - 2
            }
            return cell
        }
        guard let column = tableColumn, let trackIdx = flatTrackIndex(forRow: row) else { return nil }
        let track = tracks[trackIdx]
        let isUnavailable = isOffline && !track.isDownloaded
        let isCurrent = currentlyPlayingTrackId == track.id
        // sections mode uses selectionHighlightStyle = .none, so NSTableView doesn't
        // propagate emphasis to cells. Set it explicitly based on the row's selection
        // state so cells flip text colors correctly even after scroll-recycle.
        let emphasized = tableView.selectedRowIndexes.contains(row)
        let cellStyle: NSView.BackgroundStyle = emphasized ? .emphasized : .normal

        // Spacer column (sections mode): empty cell — the artwork overlay paints over
        // this region as a tableView subview.
        if column === spacerColumn {
            let cellId = NSUserInterfaceItemIdentifier("trackSectionSpacer")
            return tableView.makeView(withIdentifier: cellId, owner: nil)
                ?? { let v = NSView(); v.identifier = cellId; return v }()
        }

        let cell: NSTableCellView?
        switch column.identifier.rawValue {
        case "artwork":
            let c = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? TrackArtworkCell
                ?? TrackArtworkCell(identifier: column.identifier, size: Self.artworkSize,
                                    leading: Self.artworkLeadingGap)
            c.show(url: track.album?.artworkUrl)
            c.isUnavailable = isUnavailable
            cell = c
        case "number":
            let c = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NumberOrSpeakerCell
                ?? NumberOrSpeakerCell(identifier: column.identifier)
            c.accentColor = accentNSColor
            c.isUnavailable = isUnavailable
            if isCurrent {
                c.showSpeaker(playing: isPlaying)
            } else {
                let display: String
                if usesPlaylistPosition {
                    display = String(trackIdx + 1)
                } else {
                    display = track.number.map(String.init) ?? "–"
                }
                c.showNumber(display)
            }
            cell = c
        case "title":
            let c = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? TitleCell
                ?? TitleCell(identifier: column.identifier)
            // In embedded mode we hide the Artist column and stack the artist beneath
            // the title when the host wanted artist info — consistent with iTunes /
            // Apple Music layout for inline album sections.
            let inlineArtist = isEmbedded && embeddedShowsArtist
            c.accentColor = accentNSColor
            c.configure(track: track, isCurrent: isCurrent, showArtistInline: inlineArtist)
            cell = c
        case "artist":
            let c = textCell(for: column.identifier, in: tableView)
            // Show album artist (not track artist) — only album artists exist in the
            // Artists list, so this is the only value double-click navigation can resolve.
            // Featuring / track-level artist info is surfaced via the title cell's
            // optional inline subline (showArtistInline).
            c.label.stringValue = track.albumArtistName
            c.label.alignment = .left
            c.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            c.unselectedColor = .secondaryLabelColor
            cell = c
        case "album":
            let c = textCell(for: column.identifier, in: tableView)
            c.label.stringValue = track.album?.name ?? ""
            c.label.alignment = .left
            c.label.font = .systemFont(ofSize: NSFont.systemFontSize)
            c.unselectedColor = .secondaryLabelColor
            cell = c
        case "disc":
            let c = textCell(for: column.identifier, in: tableView)
            c.label.stringValue = String(track.disc)
            c.label.alignment = .right
            c.label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            c.unselectedColor = .secondaryLabelColor
            cell = c
        case "year":
            let c = textCell(for: column.identifier, in: tableView)
            c.label.stringValue = track.album?.releaseYear.map(String.init) ?? ""
            c.label.alignment = .right
            c.label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            c.unselectedColor = .secondaryLabelColor
            cell = c
        case "duration":
            let c = textCell(for: column.identifier, in: tableView)
            c.label.stringValue = track.formattedDuration
            c.label.alignment = .right
            c.label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            c.unselectedColor = .secondaryLabelColor
            // Extra right padding so the duration text has breathing room to the
            // selection pill's right edge instead of touching it. Artwork rows run the
            // pill closer to the row's edge — it has to clear the duration rather than
            // clip it — so they need more of this, not less.
            c.labelTrailingInset = showsArtwork ? 22 : 12
            cell = c
        default:
            cell = nil
        }
        if let textCell = cell as? TextCell { textCell.isUnavailable = isUnavailable }
        if let titleCell = cell as? TitleCell { titleCell.isUnavailable = isUnavailable }
        cell?.backgroundStyle = cellStyle
        return cell
    }

    private func textCell(for identifier: NSUserInterfaceItemIdentifier, in tableView: NSTableView) -> TextCell {
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? TextCell {
            return existing
        }
        return TextCell(identifier: identifier)
    }

    /// Keyboard selection in an embedded table has nowhere to scroll: the table is sized
    /// to its content, so NSTableView's own scrollRowToVisible is a no-op and arrowing
    /// past the fold moved the selection out of sight. Ask the page's scroll view
    /// instead. Only while the table has focus — a click or a restored selection
    /// shouldn't move the page under the user.
    private func scrollSelectionIntoEnclosingScrollView() {
        guard isEmbedded,
              tableView.window?.firstResponder === tableView,
              let row = tableView.selectedRowIndexes.last,
              let outer = view.enclosingScrollView,
              let document = outer.documentView else { return }
        let rect = tableView.convert(tableView.rect(ofRow: row), to: document)
        document.scrollToVisible(rect.insetBy(dx: 0, dy: -12))
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !suppressSortCallback else { return }
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let column = TrackSortColumn(rawValue: key) else {
            activeSort = nil
            onSortChange?(nil)
            rebuildHeaderMenu()
            return
        }
        activeSort = TrackSort(column: column, ascending: descriptor.ascending)
        onSortChange?(activeSort)
        rebuildHeaderMenu()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // selectionHighlightStyle = .none tells NSTableView not to redraw rows on
        // selection changes and not to flip cell backgroundStyle to .emphasized. Both
        // jobs fall to us: trigger the redraw and propagate emphasis to cells so their
        // text colors flip to white.
        tableView.enumerateAvailableRowViews { rowView, _ in
            rowView.needsDisplay = true
            let style: NSView.BackgroundStyle = rowView.isSelected ? .emphasized : .normal
            for col in 0..<rowView.numberOfColumns {
                if let cell = rowView.view(atColumn: col) as? NSTableCellView {
                    cell.backgroundStyle = style
                }
            }
        }
        scrollSelectionIntoEnclosingScrollView()
        if suppressSelectionCallback { return }
        let ids = Set(tableView.selectedRowIndexes.compactMap { row -> UUID? in
            guard let trackIdx = flatTrackIndex(forRow: row) else { return nil }
            return tracks[trackIdx].id
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
        if actions.supportsDownload {
            menu.addItem(.separator())
            // "Remove" if every selected track is already downloaded; "Download" otherwise.
            // Mixed selections show "Download" — the action skips already-downloaded tracks.
            let allDownloaded = targetTracks.allSatisfy { $0.isDownloaded }
            if allDownloaded {
                let title = isSingle ? "Remove Download" : "Remove \(targetTracks.count) Downloads"
                addItem(to: menu, title: title, action: #selector(menuRemoveDownload))
            } else {
                let title = isSingle ? "Download" : "Download \(targetTracks.count)"
                addItem(to: menu, title: title, action: #selector(menuDownload))
            }
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
    /// selects that row to make the intent visible). Section header rows return [].
    private func tracksForContextAction() -> [Track] {
        let clicked = tableView.clickedRow
        guard let clickedTrackIdx = flatTrackIndex(forRow: clicked) else { return [] }
        if tableView.selectedRowIndexes.contains(clicked) {
            return tableView.selectedRowIndexes.compactMap { row in
                guard let idx = flatTrackIndex(forRow: row) else { return nil }
                return tracks[idx]
            }
        }
        // Clicked an unselected row → just that row, and adopt it as selection so subsequent
        // actions (Play All etc. in the toolbar) target what the user expects.
        suppressSelectionCallback = true
        tableView.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        suppressSelectionCallback = false
        onSelectionChange?(Set([tracks[clickedTrackIdx].id]))
        return [tracks[clickedTrackIdx]]
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
    @objc private func menuDownload() { actions.download(tracksForContextAction()) }
    @objc private func menuRemoveDownload() { actions.removeDownload(tracksForContextAction()) }
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
/// Group-row cell that hosts a SwiftUI view (album header). Used in sections mode so
/// the caller can render the album title, artwork, action buttons via a familiar
/// SwiftUI subview while the table itself stays AppKit.
/// Leading album cover. Plain NSImageView over Nuke rather than a hosted SwiftUI view:
/// one of these exists per visible row, and hosting controllers at that rate is the
/// expensive way to draw a 36pt square.
private final class TrackArtworkCell: NSTableCellView {
    private let artwork = NSImageView()
    private var imageTask: ImageTask?
    private var loadingURL: URL?

    init(identifier: NSUserInterfaceItemIdentifier, size: CGFloat, leading: CGFloat) {
        super.init(frame: .zero)
        self.identifier = identifier
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 4
        artwork.layer?.masksToBounds = true
        addSubview(artwork)
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            artwork.widthAnchor.constraint(equalToConstant: size),
            artwork.heightAnchor.constraint(equalToConstant: size)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isUnavailable = false {
        didSet { artwork.alphaValue = isUnavailable ? 0.4 : 1 }
    }

    func show(url: URL?) {
        guard loadingURL != url else { return }
        imageTask?.cancel()
        loadingURL = url
        artwork.image = nil
        guard let url else { return }
        imageTask = ImagePipeline.shared.loadImage(with: url) { [weak self] result in
            guard let self else { return }
            if case .success(let response) = result { self.artwork.image = response.image }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        loadingURL = nil
        artwork.image = nil
    }
}

/// Divider row naming a group of tracks ("Disc 1"). Plain AppKit rather than a hosted
/// SwiftUI view: it's one label, and hosting each one costs a view controller.
private final class GroupLabelCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint!

    var text: String = "" {
        didSet { label.stringValue = text.localizedUppercase }
    }

    /// Lined up with the track titles rather than the row's edge, which is where
    /// Music.app puts it — flush left it read as a heading for the whole table.
    var leadingInset: CGFloat = 4 {
        didSet { leading.constant = leadingInset }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        // The same treatment the sidebar gives its section headings.
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset)
        NSLayoutConstraint.activate([
            leading,
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SectionHeaderCell: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?

    /// How far outside the cell's own bounds the hosted view reaches on each side, so a
    /// header can sit where the page around the table sits rather than where its rows do.
    var horizontalOutset: CGFloat = 0 {
        didSet {
            guard horizontalOutset != oldValue else { return }
            leading?.constant = -horizontalOutset
            trailing?.constant = horizontalOutset
        }
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
    }

    required init?(coder: NSCoder) { fatalError() }

    func host(view: AnyView) {
        if let h = hostingView {
            h.rootView = view
            return
        }
        let h = NSHostingView(rootView: view)
        h.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h)
        NSLayoutConstraint.activate([
            { let c = h.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -horizontalOutset); leading = c; return c }(),
            { let c = h.trailingAnchor.constraint(equalTo: trailingAnchor, constant: horizontalOutset); trailing = c; return c }(),
            h.topAnchor.constraint(equalTo: topAnchor),
            h.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        hostingView = h
    }
}

// MARK: - Cell

private final class TextCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    /// Color the label uses when the row is not selected. The delegate sets it
    /// per-column (artist/album/duration are all secondary muted).
    var unselectedColor: NSColor = .secondaryLabelColor {
        didSet { applyEmphasis() }
    }
    /// Trailing inset between the cell's right edge and the label's right edge.
    /// Defaults to 4 for tight cells; the duration column bumps this up to give
    /// breathing room next to the selection pill.
    var labelTrailingInset: CGFloat = 4 {
        didSet {
            if abs(oldValue - labelTrailingInset) > 0.5 {
                trailingConstraint?.constant = -labelTrailingInset
            }
        }
    }
    private var trailingConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        addSubview(label)
        // Deliberately not assigned to NSTableCellView.textField: that hands the label to
        // AppKit's automatic text-colour management, and under the .sourceList selection
        // style embedded tables use, it repaints titles in the lighter source-list
        // treatment — so every track read as greyed out next to the same rows in Songs.
        let trailing = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -labelTrailingInset)
        trailingConstraint = trailing
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            trailing,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    var isUnavailable = false {
        didSet { if isUnavailable != oldValue { applyEmphasis() } }
    }

    private func applyEmphasis() {
        label.textColor = backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor
            : (isUnavailable ? .tertiaryLabelColor : unselectedColor)
    }
}

/// # column cell. Switches between a track number/position and a speaker glyph for
/// the currently-playing row.
private final class NumberOrSpeakerCell: NSTableCellView {
    var accentColor: NSColor = .controlAccentColor { didSet { applyEmphasis() } }
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
        icon.isHidden = true
        addSubview(icon)

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Match the number's trailing edge — centring it left the glyph sitting in
            // the middle of the column while every digit hugged the right.
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Music.app swaps the track number for a play glyph under the pointer — it's the
    /// only hint that the number column is a click target.
    var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            applyContent()
        }
    }

    private var number: String = ""
    private var speaker: Bool?

    func showNumber(_ text: String) {
        number = text
        speaker = nil
        applyContent()
    }

    private func applyContent() {
        if let playing = speaker {
            let symbol = playing ? "speaker.wave.2.fill" : "speaker.fill"
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            icon.isHidden = false
            label.isHidden = true
            return
        }
        if isHovered {
            icon.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
            icon.isHidden = false
            label.isHidden = true
            return
        }
        label.stringValue = number
        label.isHidden = false
        icon.isHidden = true
    }

    func showSpeaker(playing: Bool) {
        speaker = playing
        applyContent()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyEmphasis() }
    }

    var isUnavailable = false {
        didSet { if isUnavailable != oldValue { applyEmphasis() } }
    }

    private func applyEmphasis() {
        let emphasized = backgroundStyle == .emphasized
        let resting: NSColor = isUnavailable ? .tertiaryLabelColor : .secondaryLabelColor
        label.textColor = emphasized ? .alternateSelectedControlTextColor : resting
        icon.contentTintColor = emphasized ? .alternateSelectedControlTextColor : accentColor
    }
}

/// Title column cell: track name + (optional) artist subline + downloaded indicator.
/// In standalone mode the artist lives in its own column so this cell only needs to
/// render the title; in embedded mode the artist column is hidden and we stack the
/// artist beneath the title when relevant. The title supports up to 2 lines either
/// way so long names wrap instead of truncating.
private final class TitleCell: NSTableCellView {
    var accentColor: NSColor = .controlAccentColor { didSet { applyEmphasis() } }
    let label = NSTextField(labelWithString: "")
    let artistLabel = NSTextField(labelWithString: "")
    let downloadedIcon = NSImageView()
    private var isCurrent: Bool = false
    var isUnavailable = false {
        didSet { if isUnavailable != oldValue { applyEmphasis() } }
    }

    /// Off when the artist is stacked under the title: two lines of title plus a line of
    /// artist is more than any row height here allows.
    private var allowsTwoLineTitle = true {
        didSet {
            guard allowsTwoLineTitle != oldValue else { return }
            applyTitleLineLimit()
        }
    }

    private func applyTitleLineLimit() {
        label.maximumNumberOfLines = allowsTwoLineTitle ? 2 : 1
        label.cell?.wraps = allowsTwoLineTitle
        label.cell?.usesSingleLineMode = !allowsTwoLineTitle
        // A wrapping label needs word wrapping, not tail truncation: with
        // .byTruncatingTail a title too long for two lines stopped mid-word against the
        // column edge with no ellipsis, while a shorter one wrapped correctly.
        // truncatesLastVisibleLine is what puts the ellipsis on line two.
        label.lineBreakMode = allowsTwoLineTitle ? .byWordWrapping : .byTruncatingTail
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.translatesAutoresizingMaskIntoConstraints = false
        // A long title takes a second line rather than truncating, as Music.app allows,
        // and never a third. The row height is fixed, so a wrapped title stays inside its
        // row and the rhythm holds — which is what the earlier single-line rule was
        // protecting, at a row height too short to contain two lines.
        label.cell?.truncatesLastVisibleLine = true
        applyTitleLineLimit()
        addSubview(label)
        // Deliberately not assigned to NSTableCellView.textField: that hands the label to
        // AppKit's automatic text-colour management, and under the .sourceList selection
        // style embedded tables use, it repaints titles in the lighter source-list
        // treatment — so every track read as greyed out next to the same rows in Songs.

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
        allowsTwoLineTitle = !showArtistInline
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
        } else if isUnavailable {
            label.textColor = .tertiaryLabelColor
            artistLabel.textColor = .tertiaryLabelColor
            downloadedIcon.contentTintColor = .tertiaryLabelColor
        } else {
            label.textColor = isCurrent ? accentColor : .labelColor
            artistLabel.textColor = .secondaryLabelColor
            downloadedIcon.contentTintColor = .secondaryLabelColor
        }
    }
}
#endif
