import Foundation
import SwiftData
import Testing
@testable import Ondu

/// The controller persists the shortcut's playlist in UserDefaults, so these share one
/// key and must not run alongside each other.
@MainActor
@Suite(.serialized)
struct PlaylistControllerLastUsedTests {
    private static let lastUsedKey = "playlists.lastUsedId"

    private let library: MusicLibrary
    private let outbox: OutboxService
    private let downloads: DownloadService

    init() throws {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        library = MusicLibrary(container: container)
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        outbox = OutboxService(musicLibrary: library, api: api)
        downloads = DownloadService(musicLibrary: library, settings: makeTestSettings())
        UserDefaults.standard.removeObject(forKey: Self.lastUsedKey)
    }

    private func makeController() -> PlaylistController {
        PlaylistController(musicLibrary: library, outbox: outbox, downloadService: downloads)
    }

    private func confirmed(_ playlist: Playlist) -> Playlist {
        Playlist(id: UUID(), name: playlist.name, trackCount: 1,
                 insertedAt: playlist.insertedAt, isFolder: false, parentId: nil)
    }

    @Test func followsThePlaylistWhenTheServerConfirmsIt() throws {
        defer { UserDefaults.standard.removeObject(forKey: Self.lastUsedKey) }
        let controller = makeController()
        let created = try #require(controller.createPlaylist(name: "Mix"))
        controller.addTracks([UUID()], to: created.id)
        #expect(controller.lastUsedPlaylistId == created.id)

        let server = confirmed(created)
        library.remapPlaylistId(from: created.id, to: server)

        #expect(controller.lastUsedPlaylistId == server.id)
        #expect(makeController().lastUsedPlaylistId == server.id)
    }

    @Test func ignoresOtherPlaylistsBeingConfirmed() throws {
        defer { UserDefaults.standard.removeObject(forKey: Self.lastUsedKey) }
        let controller = makeController()
        let used = try #require(controller.createPlaylist(name: "Used"))
        let other = try #require(controller.createPlaylist(name: "Other"))
        controller.addTracks([UUID()], to: used.id)

        library.remapPlaylistId(from: other.id, to: confirmed(other))

        #expect(controller.lastUsedPlaylistId == used.id)
    }
}
