import Foundation
import SwiftData
import Testing
@testable import MusicBox

// MARK: - Sync Response Decoding Tests

@Suite struct SyncResponseDecodingTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test func decodesFullSyncResponse() throws {
        let json = """
        {
            "artists": [{
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "Radiohead",
                "sort_name": "Radiohead",
                "slug": "radiohead",
                "album_count": 9,
                "inserted_at": "2025-01-01T00:00:00Z"
            }],
            "albums": [{
                "id": "22222222-2222-2222-2222-222222222222",
                "artist_id": "11111111-1111-1111-1111-111111111111",
                "name": "OK Computer",
                "sort_name": "OK Computer",
                "slug": "ok-computer",
                "release_year": 1997,
                "artwork_url": "https://example.com/art.jpg",
                "is_unknown": false,
                "track_count": 12,
                "inserted_at": "2025-01-01T00:00:00Z"
            }],
            "tracks": [{
                "id": "33333333-3333-3333-3333-333333333333",
                "artist_id": "11111111-1111-1111-1111-111111111111",
                "album_artist_id": "11111111-1111-1111-1111-111111111111",
                "album_id": "22222222-2222-2222-2222-222222222222",
                "name": "Paranoid Android",
                "disc": 1,
                "number": 2,
                "duration": 384.0,
                "mimetype": "audio/flac",
                "stream_url": "/tracks/33333333/stream",
                "download_url": "/tracks/33333333/download",
                "inserted_at": "2025-01-01T00:00:00Z"
            }],
            "deletions": [],
            "cursor": "cursor_abc",
            "complete": true
        }
        """
        let response = try decoder.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.artists.count == 1)
        #expect(response.artists[0].name == "Radiohead")
        #expect(response.artists[0].albumCount == 9)
        #expect(response.albums.count == 1)
        #expect(response.albums[0].releaseYear == 1997)
        #expect(response.albums[0].artworkUrl != nil)
        #expect(response.tracks.count == 1)
        #expect(response.tracks[0].name == "Paranoid Android")
        #expect(response.tracks[0].disc == 1)
        #expect(response.tracks[0].number == 2)
        #expect(response.deletions.isEmpty)
        #expect(response.cursor == "cursor_abc")
        #expect(response.complete)
    }

    @Test func artistSortNameDefaultsToName() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "The Beatles",
            "slug": "the-beatles",
            "album_count": 13,
            "inserted_at": "2025-01-01T00:00:00Z"
        }
        """
        let artist = try decoder.decode(SyncArtist.self, from: Data(json.utf8))
        #expect(artist.sortName == "The Beatles")
    }

    @Test func artistSortNameUsedWhenProvided() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "The Beatles",
            "sort_name": "Beatles, The",
            "slug": "the-beatles",
            "album_count": 13,
            "inserted_at": "2025-01-01T00:00:00Z"
        }
        """
        let artist = try decoder.decode(SyncArtist.self, from: Data(json.utf8))
        #expect(artist.sortName == "Beatles, The")
    }

    @Test func albumSortNameDefaultsToName() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "artist_id": "11111111-1111-1111-1111-111111111111",
            "name": "A Moon Shaped Pool",
            "slug": "a-moon-shaped-pool",
            "is_unknown": false,
            "track_count": 11,
            "inserted_at": "2025-01-01T00:00:00Z"
        }
        """
        let album = try decoder.decode(SyncAlbum.self, from: Data(json.utf8))
        #expect(album.sortName == "A Moon Shaped Pool")
    }

    @Test func albumOptionalFieldsNilWhenMissing() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "artist_id": "11111111-1111-1111-1111-111111111111",
            "name": "Album",
            "slug": "album",
            "is_unknown": false,
            "track_count": 1,
            "inserted_at": "2025-01-01T00:00:00Z"
        }
        """
        let album = try decoder.decode(SyncAlbum.self, from: Data(json.utf8))
        #expect(album.releaseYear == nil)
        #expect(album.artworkUrl == nil)
    }

    @Test func decodesEmptySyncResponse() throws {
        let json = """
        {
            "artists": [],
            "albums": [],
            "tracks": [],
            "deletions": [],
            "cursor": "empty_cursor",
            "complete": true
        }
        """
        let response = try decoder.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.artists.isEmpty)
        #expect(response.albums.isEmpty)
        #expect(response.tracks.isEmpty)
        #expect(response.deletions.isEmpty)
        #expect(response.complete)
    }

    @Test func decodesDeletions() throws {
        let json = """
        {
            "artists": [],
            "albums": [],
            "tracks": [],
            "deletions": [
                { "entity_type": "track", "entity_id": "33333333-3333-3333-3333-333333333333" },
                { "entity_type": "album", "entity_id": "22222222-2222-2222-2222-222222222222" }
            ],
            "cursor": "del_cursor",
            "complete": true
        }
        """
        let response = try decoder.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.deletions.count == 2)
        #expect(response.deletions[0].entityType == "track")
        #expect(response.deletions[1].entityType == "album")
    }

    @Test func decodesIncompleteResponse() throws {
        let json = """
        {
            "artists": [],
            "albums": [],
            "tracks": [],
            "deletions": [],
            "cursor": "page1_cursor",
            "complete": false
        }
        """
        let response = try decoder.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(!response.complete)
        #expect(response.cursor == "page1_cursor")
    }
}

// MARK: - SyncService State Tests

@Suite(.serialized) struct SyncServiceStateTests {
    init() {
        // Clean UserDefaults before each test
        UserDefaults.standard.removeObject(forKey: "syncCursor")
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
    }

    @Test func initialStateNoSync() {
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        #expect(!svc.hasCompletedInitialSync)
        #expect(svc.lastSyncDate == nil)
        #expect(!svc.isSyncing)
        #expect(svc.syncError == nil)
    }

    @Test func hasCompletedInitialSyncReflectsCursor() {
        UserDefaults.standard.set("some_cursor", forKey: "syncCursor")
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        #expect(svc.hasCompletedInitialSync)
    }

    @Test func lastSyncDateRestoredFromDefaults() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        UserDefaults.standard.set(date, forKey: "lastSyncDate")
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        #expect(svc.lastSyncDate != nil)
        #expect(abs(svc.lastSyncDate!.timeIntervalSince(date)) < 1)
    }

    @Test func clearSyncStateRemovesDefaults() {
        UserDefaults.standard.set("cursor", forKey: "syncCursor")
        UserDefaults.standard.set(Date(), forKey: "lastSyncDate")

        SyncService.clearSyncState()

        #expect(UserDefaults.standard.string(forKey: "syncCursor") == nil)
        #expect(UserDefaults.standard.object(forKey: "lastSyncDate") == nil)
    }

    @Test func syncProgressTracksIds() {
        var progress = SyncService.SyncProgress()
        #expect(progress.artistCount == 0)
        #expect(progress.albumCount == 0)
        #expect(progress.trackCount == 0)

        let id1 = UUID()
        let id2 = UUID()
        progress.artistIds.insert(id1)
        progress.artistIds.insert(id2)
        progress.artistIds.insert(id1) // duplicate
        #expect(progress.artistCount == 2)

        progress.albumIds.insert(UUID())
        progress.trackIds.formUnion([UUID(), UUID(), UUID()])
        #expect(progress.albumCount == 1)
        #expect(progress.trackCount == 3)
    }
    @Test func syncIfNeededRespectsMinimumInterval() async {
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        // Set lastSyncDate to just now — should skip sync due to 5-minute cooldown
        svc.lastSyncDate = Date()

        await svc.syncIfNeeded()

        // Should not have started syncing (cooldown not expired)
        #expect(!svc.isSyncing)
    }

    @Test func syncIfNeededAllowsAfterCooldown() async {
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        // Set lastSyncDate to 6 minutes ago — past the 5-minute cooldown
        svc.lastSyncDate = Date(timeIntervalSinceNow: -360)

        // This will attempt to sync and fail (no server), but it will start
        await svc.syncIfNeeded()

        // After failed sync, syncError should be set
        #expect(svc.syncError != nil)
    }

    @Test func syncSetsErrorOnFailure() async {
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        await svc.sync()

        #expect(svc.syncError != nil)
        #expect(!svc.isSyncing) // should reset after completing
    }

    @Test func syncClearsLibraryOnInitialSync() async {
        let lib = try! makeInMemoryLibrary()
        let artistId = UUID()
        lib.upsertArtists([SyncArtist(id: artistId, name: "Pre-existing", sortName: "Pre-existing",
                                      slug: "pre", albumCount: 1, insertedAt: Date())])
        lib.bumpRevision()
        #expect(lib.allArtists().count == 1)

        // No cursor means initial sync — should clear the library
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let svc = SyncService(api: api, musicLibrary: lib)

        await svc.sync()

        // Library should have been cleared (even though sync failed after)
        #expect(lib.allArtists().isEmpty)
    }

    @Test func syncProgressIsNilWhenNotSyncing() {
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let lib = try! makeInMemoryLibrary()
        let svc = SyncService(api: api, musicLibrary: lib)

        #expect(svc.syncProgress == nil)
    }
}

// MARK: - Helpers

private func makeInMemoryLibrary() throws -> MusicLibrary {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
        configurations: config
    )
    return MusicLibrary(container: container)
}
