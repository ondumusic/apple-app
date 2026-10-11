import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ArtistDetailView: View {
    @Environment(MusicLibrary.self) private var musicLibrary
    @Environment(PlayerService.self) private var player
    @Environment(NetworkMonitor.self) private var network
    @Environment(AuthService.self) private var auth

    @Environment(\.dismiss) private var dismiss

    let artist: Artist
    var downloadedOnly: Bool = false

    /// Re-read from the library on every revision. The value this page was pushed with is
    /// a snapshot: uploading a photo changes the library, not that copy, so the circle
    /// only caught up when you navigated away and back.
    @State private var liveArtist: Artist?
    private var shownArtist: Artist { liveArtist ?? artist }

    @State private var albums: [Album] = []
    @State private var hasLoadedOnce: Bool = false
    @State private var isChoosingPhoto = false
    @State private var isChoosingFile = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isUpdatingArtwork = false
    @State private var artworkError: ArtistArtworkEditor.Failure?
    @State private var lastArtworkChange: (() async throws -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    private var editor: ArtistArtworkEditor {
        ArtistArtworkEditor(api: auth.apiService, musicLibrary: musicLibrary)
    }

    private var artworkCircle: some View {
        ArtistArtworkView(artist: shownArtist, size: 120)
            .overlay {
                if isUpdatingArtwork {
                    ZStack {
                        Circle().fill(.black.opacity(0.45))
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
            }
            .contextMenu { artworkActions }
    }

    @ViewBuilder
    private var artworkActions: some View {
        let hasArtwork = !shownArtist.artwork.isEmpty
        Button(hasArtwork ? "Replace Photo…" : "Choose Photo…", systemImage: "photo") {
            isChoosingPhoto = true
        }
        // An artist photo is more often something saved from a browser than something
        // shot, so Files is a first-class way in rather than a fallback.
        Button("Choose File…", systemImage: "folder") { isChoosingFile = true }
        if hasArtwork {
            Button("Remove Photo", systemImage: "trash", role: .destructive) {
                change { try await editor.remove(artistId: artist.id) }
            }
        }
    }

    private func change(_ work: @escaping () async throws -> Void) {
        lastArtworkChange = work
        Task {
            isUpdatingArtwork = true
            defer { isUpdatingArtwork = false }
            do {
                try await work()
                reloadAlbums()
            } catch let failure as ArtistArtworkEditor.Failure {
                artworkError = failure
            } catch {
                artworkError = .failed(error.localizedDescription)
            }
        }
    }

    var body: some View {
        ScrollView {
            // Only when there is artwork, or while one is on its way. A glyph here says
            // nothing the title above it doesn't, and at this size it's decoration —
            // adding one lives in the menu, which costs no space at all.
            if !shownArtist.artwork.isEmpty || isUpdatingArtwork {
                artworkCircle
                    .padding(.top, 8)
            }

            HStack(spacing: 12) {
                Button {
                    playAll(shuffle: false)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                }

                Button {
                    playAll(shuffle: true)
                } label: {
                    Label("Shuffle All", systemImage: "shuffle")
                }
            }
            .buttonStyle(PillButtonStyle())
            .padding(.horizontal)
            .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AlbumContextMenuItems(album: album, artist: artist, downloadedOnly: downloadedOnly)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ArtistContextMenuItems(artist: artist, downloadedOnly: downloadedOnly)
                    Divider()
                    Menu("Artwork", systemImage: "photo") { artworkActions }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack")
            }
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $pickedPhoto, matching: .images)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            change { try await editor.upload(artistId: artist.id, from: url) }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            change {
                // Loaded as Data rather than an Image: it goes straight to the server,
                // and decoding it into a UIImage first would only lose the original.
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ArtistArtworkEditor.Failure.notAnImage
                }
                try await editor.upload(artistId: artist.id, data: data)
            }
        }
        .artworkFailureAlert(
            $artworkError,
            retry: { if let work = lastArtworkChange { change(work) } },
            chooseAnother: { isChoosingPhoto = true }
        )
        .onChange(of: musicLibrary.revision, initial: true) {
            reloadAlbums()
        }
        .onChange(of: musicLibrary.downloadChanged) {
            guard downloadedOnly else { return }
            reloadAlbums()
        }
    }

    private func reloadAlbums() {
        liveArtist = musicLibrary.artist(artist.id)
        albums =
            downloadedOnly
            ? musicLibrary.downloadedAlbumsForArtist(artist.id)
            : musicLibrary.albumsForArtist(artist.id)

        if downloadedOnly && hasLoadedOnce && albums.isEmpty {
            dismiss()
        }
        hasLoadedOnce = true
    }

    private func playAll(shuffle: Bool) {
        let albums = musicLibrary.albumsWithTracksForArtist(artist.id)
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
}
