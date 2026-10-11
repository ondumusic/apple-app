#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ArtistsViewMac: View {
    /// When non-nil, the master list selects this artist on first load instead of
    /// defaulting to artists.first. MacOSContentView sets it from .navigateToArtist
    /// so opening this view from "Go to Artist" lands directly on the right artist
    /// without flickering through the default first-artist selection.
    @Binding var pendingArtistSelection: UUID?

    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(DownloadService.self) private var downloadService
    @Environment(AuthService.self) private var auth

    @AppStorage("libraryFilter") private var libraryFilter: LibraryFilter = .all
    /// Persisted like the sidebar's, so the split survives a relaunch.
    @AppStorage("macArtistListWidth") private var artistListWidth: Double = 240
    @State private var artists: [Artist] = []
    @State private var artworkError: ArtistArtworkEditor.Failure?
    @State private var lastArtworkChange: (() async throws -> Void)?
    @State private var lastArtworkArtist: Artist?
    @State private var selectedArtistId: Artist.ID?

    var body: some View {
        ChromedPage {
            ContentHeader(backDestination: nil) {
                LibraryOptionsMenu(filter: $libraryFilter)
            }
        } content: { topInset in
            // Plain HStack with a manual divider — HSplitView was rendering above the
            // window toolbar (it doesn't respect the parent's toolbar safe area), and the
            // nested NavigationSplitView had its own grey chrome problem. A regular HStack
            // sits cleanly inside the outer detail column.
            if artists.isEmpty {
                LibraryEmptyState(subject: .artists, isFiltered: libraryFilter == .downloaded) {
                    libraryFilter = .all
                }
                .padding(.top, topInset)
            } else {
                HStack(spacing: 0) {
                    ArtistsTable(
                        artists: artists,
                        selection: $selectedArtistId,
                        actions: artistActions,
                        accent: settings.resolvedAccentColor,
                        showsArtwork: settings.showArtistArtwork,
                        topContentInset: topInset
                    )
                    .background(.background)
                    .frame(width: artistListWidth)

                    SidebarDivider(width: $artistListWidth, range: 180...420)
                        .padding(.top, topInset)

                    Group {
                        if let id = selectedArtistId, let artist = artists.first(where: { $0.id == id }) {
                            ArtistDetailMac(artist: artist, isEmbedded: true)
                                .id(artist.id)
                        } else {
                            ContentUnavailableView("Select an Artist", systemImage: "music.mic")
                                .padding(.top, topInset)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .artworkFailureAlert(
            $artworkError,
            retry: { if let work = lastArtworkChange { Task { await runArtworkChange(work) } } },
            chooseAnother: { if let artist = lastArtworkArtist { chooseArtwork(for: artist) } }
        )
        .onChange(of: musicLibrary.revision, initial: true) { reloadArtists() }
        .onChange(of: libraryFilter) { reloadArtists() }
        .onChange(of: pendingArtistSelection) { _, newValue in
            // Late navigation while ArtistsViewMac is already onscreen.
            if let id = newValue, artists.contains(where: { $0.id == id }) {
                selectedArtistId = id
                pendingArtistSelection = nil
            }
        }
    }

    private var artistActions: ArtistActions {
        var actions = ArtistActions.standard(
            player: player, musicLibrary: musicLibrary,
            network: network, downloadService: downloadService)
        actions.supportsArtwork = true
        actions.chooseArtwork = { artist in chooseArtwork(for: artist) }
        actions.removeArtwork = { artist in
            lastArtworkArtist = artist
            Task { await runArtworkChange { try await artworkEditor.remove(artistId: artist.id) } }
        }
        return actions
    }

    private var artworkEditor: ArtistArtworkEditor {
        ArtistArtworkEditor(api: auth.apiService, musicLibrary: musicLibrary)
    }

    private func chooseArtwork(for artist: Artist) {
        lastArtworkArtist = artist
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await runArtworkChange { try await artworkEditor.upload(artistId: artist.id, from: url) } }
    }

    private func runArtworkChange(_ work: @escaping () async throws -> Void) async {
        lastArtworkChange = work
        do {
            try await work()
        } catch let failure as ArtistArtworkEditor.Failure {
            artworkError = failure
        } catch {
            artworkError = .failed(error.localizedDescription)
        }
    }

    private func reloadArtists() {
        artists = libraryFilter == .downloaded ? musicLibrary.downloadedArtists() : musicLibrary.allArtists()
        // Prefer a pending navigation request, then keep current, then fall back to the
        // first artist. The pending value is consumed once.
        if let pending = pendingArtistSelection, artists.contains(where: { $0.id == pending }) {
            selectedArtistId = pending
            pendingArtistSelection = nil
        } else if selectedArtistId == nil || !artists.contains(where: { $0.id == selectedArtistId }) {
            selectedArtistId = artists.first?.id
        }
    }
}
#endif
