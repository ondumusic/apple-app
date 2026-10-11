#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ArtistDetailMac: View {
    let artist: Artist
    /// True inside ArtistsViewMac's detail pane, false when pushed as its own page.
    var isEmbedded = false

    /// Re-read from the library on every revision. Embedded, the list hands this page a
    /// fresh artist each time it reloads; pushed on its own, the value it was given is a
    /// snapshot and an uploaded photo would never appear.
    @State private var liveArtist: Artist?
    private var shownArtist: Artist { liveArtist ?? artist }

    @Environment(\.dismiss) private var dismiss
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService
    @Environment(AuthService.self) private var auth

    @State private var albums: [Album] = []
    /// Selection is hoisted up to the artist level so the single TracksTable can carry
    /// it across all album sections (cmd-click + shift-range work natively).
    @State private var selection: Set<UUID> = []
    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    @State private var paneWidth: CGFloat = 0
    @State private var isUpdatingArtwork = false
    @State private var artworkError: ArtistArtworkEditor.Failure?
    @State private var lastArtworkChange: (() async throws -> Void)?
    @State private var isDropTargeted = false

    private var totalSongs: Int {
        albums.reduce(0) { $0 + ($1.tracks?.count ?? 0) }
    }

    /// Flat concatenation of every album's tracks in display order. Selection indexes
    /// and onPlay indexes refer to this array.
    private var allTracks: [Track] {
        albums.flatMap { $0.tracks ?? [] }
    }

    private var sections: [TracksTableSection] {
        albums.map { TracksTableSection(id: $0.id, album: $0, tracks: $0.tracks ?? []) }
    }

    @Environment(\.pageTopInset) private var pageTopInset

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TracksTable(
                tracks: allTracks,
                selection: $selection,
                onPlay: playTrack(at:),
                actions: trackActions,
                showArtist: false,
                showAlbum: false,
                isOffline: !network.isOnline,
                accent: settings.resolvedAccentColor,
                currentlyPlayingTrackId: player.currentTrack?.id,
                isPlaying: player.isPlaying,
                hidesColumnHeaders: true,
                rowHeight: DetailPageMetrics.trackRowHeight,
                embeddedStyle: true,
                sections: sections,
                groupLabels: TrackGrouping.discLabels(forSections: albums.map { $0.tracks ?? [] }),
                sectionHeader: { album in
                    AnyView(
                        AlbumSectionHeader(
                            album: album,
                            onPlay: { playAlbum(album, shuffle: false) },
                            onShuffle: { playAlbum(album, shuffle: true) },
                            onDownload: { downloadAlbum(album) },
                            onCancelDownload: { cancelAlbumDownload(album) },
                            leadingInset: isCompact ? 20 : 240,
                            inlineArtwork: isCompact
                        )
                        // Inject services so the header can reflect download state live —
                        // NSHostingView creates its own environment scope, so we need to
                        // pass these explicitly.
                        .environment(musicLibrary)
                        .environment(downloadService)
                    )
                },
                sectionHeaderHeight: isCompact ? 96 : 80,
                artwork: artworkOverlay,
                artworkSize: 160,
                artworkInset: 20,
                topContentInset: pageTopInset,
                pageHeader: AnyView(
                    header
                        .padding(.horizontal, DetailPageMetrics.horizontalInset)
                        .padding(.top, DetailPageMetrics.topInset)
                        .padding(.bottom, DetailPageMetrics.bottomInset)
                        // Hosted inside the table, out of reach of this view's environment.
                        .environment(musicLibrary)
                        .environment(settings)
                        .environment(player)
                        .environment(network)
                        .environment(downloadService)
                        .environment(auth)
                )
            )
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                paneWidth = $0
            }
        }
        // The compact switch is a hard breakpoint — the artwork moves from a gutter to
        // inline and the header changes height — so there's nothing to animate between.
        // Inheriting an animation made the track list slide across as it flipped.
        .animation(nil, value: isCompact)
        .artworkFailureAlert(
            $artworkError,
            retry: { if let work = lastArtworkChange { Task { await upload(work) } } },
            chooseAnother: { chooseArtwork() }
        )
        .pageBackground()
        .onChange(of: musicLibrary.revision, initial: true) { reload() }
        .onChange(of: libraryFilter) { reload() }
        .onChange(of: musicLibrary.downloadChanged) { reload() }
    }

    /// The split layout reserves a fixed 200pt for the artwork, which leaves the track
    /// titles wrapping once the pane is narrow — and the artist list means the pane is a
    /// lot narrower than the window. Below this the section header takes the cover
    /// inline and the rows get the full width instead of a squeezed column.
    private static let splitLayoutMinWidth: CGFloat = 640
    private var isCompact: Bool { paneWidth > 0 && paneWidth < Self.splitLayoutMinWidth }

    private var artworkOverlay: ((Album) -> AnyView)? {
        isCompact ? nil : { album in AnyView(AlbumArtworkOverlay(album: album)) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            // Only when there is artwork — see ArtistDetailView for why.
            // Also while uploading: on an artist with no artwork the circle would
            // otherwise vanish the moment the file lands and reappear when the server
            // answers, which reads as the drop having been refused.
            if !shownArtist.artwork.isEmpty || isDropTargeted || isUpdatingArtwork {
                headerArtwork
                    .contextMenu { artworkActions }
                    .padding(.trailing, Spacing.related)
            }
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(artist.name)
                    .font(.largeTitle.bold())
                DetailMetadataLine(parts: metadataParts)
            }
            Spacer()
            PlayShuffleButtons(
                accent: settings.resolvedAccentColor,
                onPlay: { playAll(shuffle: false) },
                onShuffle: { playAll(shuffle: true) },
                isEnabled: !albums.isEmpty
            )
            artworkMenu
        }
        // Dropping a picture on the header is the gesture people try first, and it saves
        // the panel entirely.
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data else { return }
                Task { @MainActor in await upload { try await editor.upload(artistId: artist.id, data: data) } }
            }
            return true
        }
    }

    /// One thing at a time. Overlaying these drew the placeholder mic behind the drop
    /// target's photo glyph — two different symbols at two different sizes, swapping as
    /// fast as the drag.
    @ViewBuilder
    private var headerArtwork: some View {
        if isDropTargeted {
            dropTarget.frame(width: Self.headerArtworkSize, height: Self.headerArtworkSize)
        } else if shownArtist.artwork.isEmpty, isUpdatingArtwork {
            ZStack {
                Circle().fill(.quaternary)
                ProgressView().controlSize(.small)
            }
            .frame(width: Self.headerArtworkSize, height: Self.headerArtworkSize)
        } else {
            ArtistArtworkView(artist: shownArtist, size: Self.headerArtworkSize)
                .overlay { if isUpdatingArtwork { uploadingOverlay } }
        }
    }

    private static let headerArtworkSize: CGFloat = 96

    /// Says where the picture is going. The header takes the drop — a 96pt circle is a
    /// small target to hit — but the circle is what lights up, so it's clear what will
    /// change rather than that something, somewhere, accepted it.
    private var dropTarget: some View {
        ZStack {
            Circle().fill(.thinMaterial)
            Circle()
                .strokeBorder(settings.resolvedAccentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(settings.resolvedAccentColor)
        }
    }

    private var uploadingOverlay: some View {
        ZStack {
            Circle().fill(.black.opacity(0.45))
            ProgressView().controlSize(.small).tint(.white)
        }
    }

    @ViewBuilder
    private var artworkActions: some View {
        Button(shownArtist.artwork.isEmpty ? "Choose Artwork…" : "Replace Artwork…") { chooseArtwork() }
        Button("Remove Artwork") {
            Task { await upload { try await editor.remove(artistId: artist.id) } }
        }
        .disabled(shownArtist.artwork.isEmpty)
    }

    private var artworkMenu: some View {
        Menu {
            artworkActions
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(AccentActionButtonStyle(accent: settings.resolvedAccentColor, isCircular: true))
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isUpdatingArtwork)
        .help("Artist artwork")
    }

    private var editor: ArtistArtworkEditor {
        ArtistArtworkEditor(api: auth.apiService, musicLibrary: musicLibrary)
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await upload { try await editor.upload(artistId: artist.id, from: url) } }
    }

    private func upload(_ work: @escaping () async throws -> Void) async {
        lastArtworkChange = work
        isUpdatingArtwork = true
        defer { isUpdatingArtwork = false }
        do {
            try await work()
            reload()
        } catch let failure as ArtistArtworkEditor.Failure {
            artworkError = failure
        } catch {
            artworkError = .failed(error.localizedDescription)
        }
    }

    private var metadataParts: [String] {
        [
            String(AttributedString(localized: "^[\(albums.count) album](inflect: true)").characters),
            String(AttributedString(localized: "^[\(totalSongs) song](inflect: true)").characters),
        ]
    }

    private var trackActions: TrackActions {
        // Album-specific artwork URL is supplied per call inside playTrack/playAlbum;
        // generic actions fall back to no artwork — fine for context-menu-driven playback.
        .standard(player: player, musicLibrary: musicLibrary, network: network, downloadService: downloadService)
    }

    private func reload() {
        liveArtist = musicLibrary.artist(artist.id)
        let all = musicLibrary.albumsWithTracksForArtist(artist.id)
        guard libraryFilter == .downloaded else {
            albums = all
            return
        }
        // The filter reached the artist list but stopped here, so narrowing to
        // downloads and opening an artist still listed everything they have. Albums keep
        // only their downloaded tracks, and an album left with none drops out.
        albums = all.compactMap { album in
            let downloaded = (album.tracks ?? []).filter(\.isDownloaded)
            guard !downloaded.isEmpty else { return nil }
            var trimmed = album
            trimmed.tracks = downloaded
            return trimmed
        }
    }

    private func playTrack(at index: Int) {
        guard allTracks.indices.contains(index) else { return }
        let target = allTracks[index]
        let available = musicLibrary.availableTracks(allTracks, isOnline: network.isOnline)
        guard let queueIndex = available.firstIndex(where: { $0.id == target.id }) else { return }
        let artwork = albums.first { $0.id == target.albumId }?.artworkUrl
        player.requestPlay {
            player.playNow(tracks: available, startingAt: queueIndex, artworkURL: artwork)
        }
    }

    private func playAll(shuffle: Bool) {
        let allItems = albums.flatMap { album in
            (album.tracks ?? []).map { QueueItem(track: $0, artworkURL: album.artworkUrl) }
        }
        let items = musicLibrary.availableItems(allItems, isOnline: network.isOnline)
        guard !items.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(queue: items) }
        } else {
            player.requestPlay { player.playNow(queue: items) }
        }
    }

    private func downloadAlbum(_ album: Album) {
        guard let fullAlbum = musicLibrary.albumWithTracks(album.id) else { return }
        let albumArtist =
            musicLibrary.artist(album.artistId)
            ?? Artist(id: album.artistId, name: artist.name, sortName: artist.sortName, slug: artist.slug)
        downloadService.download(album: fullAlbum, artist: albumArtist)
    }

    private func cancelAlbumDownload(_ album: Album) {
        downloadService.cancelAlbumDownloads(albumId: album.id)
    }

    private func playAlbum(_ album: Album, shuffle: Bool) {
        let tracks = album.tracks ?? []
        let available = musicLibrary.availableTracks(tracks, isOnline: network.isOnline)
        guard !available.isEmpty else { return }
        if shuffle {
            player.requestPlay { player.playShuffled(tracks: available, artworkURL: album.artworkUrl) }
        } else {
            player.requestPlay { player.playNow(tracks: available, artworkURL: album.artworkUrl) }
        }
    }
}

#endif
