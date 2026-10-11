#if os(macOS)
import AppKit
import Nuke

/// One album cell. Plain AppKit rather than an NSHostingView wrapping the shared
/// SwiftUI AlbumCard: a hosting view per cell gives back most of what recycling buys,
/// and loading Nuke directly lets the cell cancel an in-flight request when it's
/// recycled — which is the bulk of the win when scrolling a large library.
final class AlbumGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("AlbumGridItem")

    /// Set by the grid so selection paints the app accent rather than the system one.
    var accentColor: NSColor = .controlAccentColor { didSet { applySelection() } }
    /// False while the grid isn't first responder, so selection reads as inactive the
    /// way every other AppKit selection in the app does.
    var isEmphasized: Bool = true { didSet { applySelection() } }
    var onPlay: (() -> Void)?

    private let artwork = NSImageView()
    private let artworkContainer = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let playButton = NSButton()
    private let scrim = NSView()
    private var loadingURL: URL?
    private var imageTask: ImageTask?

    override var isSelected: Bool {
        didSet { applySelection() }
    }

    /// Rubber-band membership arrives here, not through isSelected — NSCollectionView
    /// only commits the selection on mouse-up, so drawing isSelected alone left the
    /// marquee empty until release. Finder highlights as the rectangle passes over.
    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { applySelection() }
    }

    /// Selected, or about to be by the rectangle currently being dragged over it.
    private var drawsSelected: Bool {
        switch highlightState {
        case .forSelection: return true
        case .forDeselection: return false
        default: return isSelected
        }
    }

    /// Driven by the collection view rather than a tracking area of this cell's own:
    /// cells move under a stationary cursor while scrolling and never get mouseExited,
    /// so per-cell tracking left play buttons stuck on several covers at once.
    var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue else { return }
            scrim.isHidden = !isHovered
            playButton.isHidden = !isHovered
        }
    }

    /// Passed through to the item's view: NSCollectionView hides the items being
    /// dragged, and declining that is the only way to avoid a flash — restoring them
    /// afterwards is always at least one frame late.
    var suppressesHiding: Bool {
        get { (view as? DragVisibleView)?.suppressesHiding ?? false }
        set {
            guard let view = view as? DragVisibleView else { return }
            view.suppressesHiding = newValue
            if newValue { view.isHidden = false }
        }
    }

    override func loadView() {
        view = DragVisibleView()
        view.wantsLayer = true

        artworkContainer.translatesAutoresizingMaskIntoConstraints = false
        artworkContainer.wantsLayer = true
        artworkContainer.layer?.cornerRadius = 8
        artworkContainer.layer?.masksToBounds = true
        // Pale covers otherwise dissolve into the page — the grid sits on a light
        // background. Same reasoning as the SwiftUI card's border.
        artworkContainer.layer?.borderWidth = 0.5
        artworkContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        view.addSubview(artworkContainer)

        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artworkContainer.addSubview(artwork)

        // Sits under the play button so it stays legible on a white sleeve.
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        scrim.isHidden = true
        artworkContainer.addSubview(scrim)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.bezelStyle = .circular
        playButton.isBordered = false
        playButton.wantsLayer = true
        playButton.layer?.cornerRadius = 17
        playButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        playButton.image = NSImage(
            systemSymbolName: "play.fill",
            accessibilityDescription: NSLocalizedString("Play", comment: "")
        )
        playButton.contentTintColor = .black
        playButton.imageScaling = .scaleProportionallyDown
        playButton.target = self
        playButton.action = #selector(handlePlay)
        playButton.isHidden = true
        playButton.toolTip = NSLocalizedString("Play", comment: "")
        artworkContainer.addSubview(playButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        applyTitleLines()
        view.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.cell?.usesSingleLineMode = true
        view.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            artworkContainer.topAnchor.constraint(equalTo: view.topAnchor),
            artworkContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            artworkContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            artworkContainer.heightAnchor.constraint(equalTo: artworkContainer.widthAnchor),

            artwork.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: artworkContainer.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: artworkContainer.trailingAnchor),
            artwork.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor),

            scrim.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: artworkContainer.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: artworkContainer.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor),

            playButton.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: artworkContainer.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 34),
            playButton.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.topAnchor.constraint(equalTo: artworkContainer.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    /// Two lines, as Music.app gives it — a long album name truncated to one line was
    /// the reason the second line had to be something short like a year. One where the
    /// caller reserves the height and a wrap would push the caption out of it.
    var titleLines: Int = 2 {
        didSet {
            guard titleLines != oldValue else { return }
            applyTitleLines()
        }
    }

    private func applyTitleLines() {
        titleLabel.maximumNumberOfLines = titleLines
        // maximumNumberOfLines alone doesn't wrap an NSTextField — the cell has to be
        // told it may, and to truncate the line it stops on rather than the first.
        titleLabel.cell?.usesSingleLineMode = titleLines < 2
        titleLabel.cell?.wraps = titleLines >= 2
        titleLabel.cell?.truncatesLastVisibleLine = true
    }

    func configure(album: Album) {
        titleLabel.stringValue = album.name
        // The artist, not the year — the year says less about which album this is, and
        // Music.app doesn't show one in the grid at all.
        subtitleLabel.stringValue = album.artistName ?? ""
        applySelection()

        guard loadingURL != album.artworkUrl else { return }
        imageTask?.cancel()
        loadingURL = album.artworkUrl
        artwork.image = nil
        guard let url = album.artworkUrl else { return }
        imageTask = ImagePipeline.shared.loadImage(
            with: ImageRequest(url: url, processors: [.resize(width: 400)])
        ) { [weak self] result in
            guard let self, self.loadingURL == url else { return }  // recycled mid-flight
            if case .success(let response) = result { self.artwork.image = response.image }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // The whole reason this isn't a hosting view: a cell scrolled past cancels its
        // request instead of finishing work for something nobody is looking at.
        imageTask?.cancel()
        imageTask = nil
        loadingURL = nil
        artwork.image = nil
        isHovered = false
        highlightState = .none
        suppressesHiding = false
    }

    /// Photos-style: a ring around the sleeve and the title picking up the accent, rather
    /// than a wash over the artwork — a translucent fill across a 300pt cover just makes
    /// it muddy.
    private func applySelection() {
        let on = drawsSelected
        let color = isEmphasized ? accentColor : .tertiaryLabelColor
        artworkContainer.layer?.borderWidth = on ? 3 : 0.5
        artworkContainer.layer?.borderColor =
            on
            ? color.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        titleLabel.textColor = on ? color : .labelColor
    }

    @objc private func handlePlay() { onPlay?() }

}

/// Declines `isHidden = true` while a drag is in flight. AppKit hides a drag's source
/// views for its duration, which leaves holes in a grid or table; the ghost under the
/// cursor already says what's moving, and Finder leaves the originals in place.
final class DragVisibleView: NSView {
    var suppressesHiding = false

    override var isHidden: Bool {
        get { super.isHidden }
        set {
            guard !(suppressesHiding && newValue) else { return }
            super.isHidden = newValue
        }
    }
}
#endif
