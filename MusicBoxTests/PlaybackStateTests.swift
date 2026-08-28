import Foundation
import SwiftData
import Testing
@testable import MusicBox

// MARK: - Helpers

private let now = Date()

private func makeTestLibrary() throws -> MusicLibrary {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
             LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
        configurations: config
    )
    return MusicLibrary(container: container)
}

/// Seeds a library with one artist, one album and `count` tracks, returning the track ids in order.
private func seedTracks(_ lib: MusicLibrary, count: Int) -> [UUID] {
    let artistId = UUID()
    let albumId = UUID()
    lib.upsertArtists([SyncArtist(id: artistId, name: "Artist", sortName: "Artist",
                                  slug: "artist", albumCount: 1, insertedAt: now)])
    lib.upsertAlbums([SyncAlbum(id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                                slug: "album", releaseYear: nil, artworkUrl: nil,
                                isUnknown: false, trackCount: count, insertedAt: now)])
    let tracks = (0..<count).map { i in
        SyncTrack(id: UUID(), artistId: artistId, albumArtistId: artistId, albumId: albumId,
                  name: "Track \(i)", disc: 1, number: i + 1, duration: 200,
                  mimetype: "audio/mp4", streamUrl: "/stream/\(i)",
                  downloadUrl: "/download/\(i)", insertedAt: now)
    }
    lib.upsertTracks(tracks)
    lib.bumpRevision()
    return tracks.map(\.id)
}

private func makeStore() -> PlaybackStateStore {
    let id = UUID().uuidString
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("playback-state-tests/\(id).json")
    let defaults = UserDefaults(suiteName: "playback-state-tests.\(id)")!
    return PlaybackStateStore(fileURL: url, defaults: defaults)
}

private func makePlayer(library: MusicLibrary?, store: PlaybackStateStore) -> PlayerService {
    let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
    return PlayerService(api: api, settings: SettingsStore(), musicLibrary: library, stateStore: store)
}

// MARK: - Store

@Suite(.serialized)
struct PlaybackStateStoreTests {

    @Test func roundTripsTheQueueThroughDisk() {
        let store = makeStore()
        let state = PlaybackState(trackIds: [UUID(), UUID()], currentIndex: 1, shuffledIndices: [1, 0])
        store.save(state)

        #expect(store.load() == state)
    }

    @Test func roundTripsThePosition() {
        let store = makeStore()
        let position = PlaybackPosition(trackId: UUID(), elapsed: 42.5)
        store.savePosition(position)

        #expect(store.loadPosition() == position)
    }

    @Test func loadPositionReturnsNilWhenNothingSaved() {
        #expect(makeStore().loadPosition() == nil)
    }

    @Test func loadReturnsNilWhenNothingSaved() {
        #expect(makeStore().load() == nil)
    }

    @Test func clearRemovesBothHalves() {
        let store = makeStore()
        store.save(PlaybackState(trackIds: [UUID()], currentIndex: 0, shuffledIndices: nil))
        store.savePosition(PlaybackPosition(trackId: UUID(), elapsed: 10))
        store.clear()

        #expect(store.load() == nil)
        #expect(store.loadPosition() == nil)
    }
}

// MARK: - Restore

@Suite(.serialized)
struct PlayerStateRestoreTests {

    @Test func restoresQueueAndPositionOnLaunch() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 4)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids, currentIndex: 2, shuffledIndices: nil))
        store.savePosition(PlaybackPosition(trackId: ids[2], elapsed: 61))

        let player = makePlayer(library: lib, store: store)

        #expect(player.queue.map(\.track.id) == ids)
        #expect(player.currentIndex == 2)
        #expect(player.currentTrack?.id == ids[2])
        #expect(player.progress == 61)
        #expect(!player.isPlaying)
    }

    @Test func ignoresAPositionBelongingToADifferentTrack() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 3)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids, currentIndex: 0, shuffledIndices: nil))
        store.savePosition(PlaybackPosition(trackId: ids[2], elapsed: 90))

        let player = makePlayer(library: lib, store: store)

        #expect(player.currentTrack?.id == ids[0])
        #expect(player.progress == 0)
    }

    @Test func restoresShuffleOrder() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 3)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids, currentIndex: 0, shuffledIndices: [2, 0, 1]))

        let player = makePlayer(library: lib, store: store)

        #expect(player.shuffledIndices == [2, 0, 1])
        #expect(player.currentTrack?.id == ids[2])
    }

    @Test func dropsSnapshotWhenATrackNoLongerExists() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 2)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids + [UUID()], currentIndex: 0, shuffledIndices: nil))

        let player = makePlayer(library: lib, store: store)

        #expect(player.queue.isEmpty)
        #expect(player.currentTrack == nil)
    }

    @Test func ignoresShuffleOrderThatNoLongerMatchesTheQueue() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 3)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids, currentIndex: 0, shuffledIndices: [1, 0]))

        let player = makePlayer(library: lib, store: store)

        #expect(player.shuffledIndices == nil)
        #expect(player.queue.count == 3)
    }

    @Test func clampsAnOutOfRangeIndex() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 2)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids, currentIndex: 99, shuffledIndices: nil))

        let player = makePlayer(library: lib, store: store)

        #expect(player.currentIndex == 1)
        #expect(player.currentTrack?.id == ids[1])
    }

    @Test func restoresNothingWithoutALibrary() {
        let store = makeStore()
        store.save(PlaybackState(trackIds: [UUID()], currentIndex: 0, shuffledIndices: nil))

        let player = makePlayer(library: nil, store: store)

        #expect(player.queue.isEmpty)
    }
}

// MARK: - Save

@Suite(.serialized)
struct PlayerStateSaveTests {

    @Test func savesTheQueueOnMutation() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 3)
        let store = makeStore()
        let player = makePlayer(library: lib, store: store)

        player.playNext(queue: ids.compactMap { lib.track($0) }.map { QueueItem(track: $0) })

        let saved = store.load()
        #expect(saved?.trackIds == ids)
    }

    @Test func anEmptyQueueLeavesTheLastSnapshotAlone() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 2)
        let store = makeStore()
        let state = PlaybackState(trackIds: ids, currentIndex: 0, shuffledIndices: nil)
        store.save(state)

        let player = makePlayer(library: nil, store: store)
        player.savePlaybackState()

        #expect(store.load() == state)
    }

    @Test func savedShuffleOrderSurvivesAToggle() throws {
        let lib = try makeTestLibrary()
        let ids = seedTracks(lib, count: 5)
        let store = makeStore()
        store.save(PlaybackState(trackIds: ids, currentIndex: 0, shuffledIndices: nil))
        let player = makePlayer(library: lib, store: store)

        player.toggleShuffle()

        #expect(store.load()?.shuffledIndices?.sorted() == Array(0..<5))
    }
}
