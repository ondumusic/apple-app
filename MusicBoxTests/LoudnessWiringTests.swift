import Foundation
import SwiftData
import Testing
@testable import MusicBox

/// The path from the Settings toggle to the gain on the playing track: the setting's
/// didSet, the callback PlayerService installs on it, and the album-vs-track choice.
/// Everything below this is AVPlayer's own `volume`.
@Suite(.serialized)
struct LoudnessWiringTests {

    func makeLibrary() throws -> MusicLibrary {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return MusicLibrary(container: container)
    }

    /// One album, one track per entry in `lufs`, returning the track ids in order.
    func seed(_ lib: MusicLibrary, lufs: [Double?]) -> [UUID] {
        let artistId = UUID(), albumId = UUID(), now = Date()
        lib.upsertArtists([SyncArtist(id: artistId, name: "Artist", sortName: "Artist",
                                      slug: "artist", albumCount: 1, insertedAt: now)])
        lib.upsertAlbums([SyncAlbum(id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                                    slug: "album", releaseYear: nil, artworkUrl: nil, isUnknown: false,
                                    trackCount: lufs.count, insertedAt: now)])
        let tracks = lufs.enumerated().map { index, value in
            SyncTrack(id: UUID(), artistId: artistId, albumArtistId: artistId, albumId: albumId,
                      name: "Track \(index)", disc: 1, number: index + 1, duration: 200,
                      mimetype: "audio/mp4", streamUrl: "/s/\(index)", downloadUrl: "/d/\(index)",
                      insertedAt: now, lufs: value)
        }
        lib.upsertTracks(tracks)
        lib.bumpRevision()
        return tracks.map(\.id)
    }

    /// Restores a queue so `currentTrack` is set without needing a server to play from.
    func makePlayer(_ lib: MusicLibrary, queue ids: [UUID],
                            settings: SettingsStore) async -> PlayerService {
        let store = PlaybackStateStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("loudness-wiring/\(UUID().uuidString).json"),
            defaults: UserDefaults(suiteName: "loudness-wiring.\(UUID().uuidString)")!
        )
        store.save(PlaybackState(trackIds: ids, currentIndex: 0, shuffledIndices: nil))
        await store.flush()
        let api = APIService(baseURL: URL(string: "http://localhost")!, sessionToken: "test")
        let player = PlayerService(api: api, settings: settings, musicLibrary: lib, stateStore: store)
        await player.restoreTask?.value
        return player
    }

    func dB(_ gain: Float) -> Double { 20 * log10(Double(gain)) }

    @Test func togglingTheSettingReappliesToTheTrackAlreadyPlaying() async throws {
        let lib = try makeLibrary()
        // Mixed album so the queue isn't a single-album one: this is track gain.
        let ids = seed(lib, lufs: [-4, -23])
        let settings = makeTestSettings()
        settings.normalizeVolume = false
        let player = await makePlayer(lib, queue: [ids[0]], settings: settings)

        settings.normalizeVolume = true
        #expect(dB(player.primaryGain) < -9)

        settings.normalizeVolume = false
        #expect(player.primaryGain == 1)
    }

    @Test func aQueueOfOneAlbumTakesTheAlbumGain() async throws {
        let lib = try makeLibrary()
        let ids = seed(lib, lufs: [-4, -23])
        let settings = makeTestSettings()
        let player = await makePlayer(lib, queue: ids, settings: settings)

        settings.normalizeVolume = true
        // The album sits near -7 LUFS, so its gain is shallower than the -10 the loud
        // track would get on its own.
        let albumGain = dB(player.primaryGain)
        #expect(albumGain > -9)
        #expect(albumGain < -5)
    }

    @Test func aMixedQueueTakesTheTrackGain() async throws {
        let lib = try makeLibrary()
        let loud = seed(lib, lufs: [-4])
        let quiet = seed(lib, lufs: [-23])
        let settings = makeTestSettings()
        let player = await makePlayer(lib, queue: [loud[0], quiet[0]], settings: settings)

        settings.normalizeVolume = true
        #expect(dB(player.primaryGain) < -9)
    }

    @Test func anUnmeasuredTrackIsLeftAlone() async throws {
        let lib = try makeLibrary()
        let ids = seed(lib, lufs: [nil, nil])
        let settings = makeTestSettings()
        let player = await makePlayer(lib, queue: ids, settings: settings)

        settings.normalizeVolume = true
        #expect(player.primaryGain == 1)
    }
}

extension LoudnessWiringTests {

    /// A lone track is levelled as a track even though it trivially satisfies "every
    /// track in the queue shares an album".
    @Test func oneTrackOnItsOwnTakesTheTrackGain() async throws {
        let lib = try makeLibrary()
        let ids = seed(lib, lufs: [-4, -23])
        let settings = makeTestSettings()
        let player = await makePlayer(lib, queue: [ids[0]], settings: settings)

        settings.normalizeVolume = true
        #expect(dB(player.primaryGain) < -9)
    }
}

/// `FileManager.enumerator` returns symlink-resolved URLs while `urls(for:in:)` does not.
/// On iOS the container is under `/var`, a symlink to `/private/var`, so building the
/// stored path by stripping a prefix produced an absolute path glued onto
/// "MusicBox/Downloads/" and every reconciled track pointed at nothing.
@Suite
struct DownloadManifestPathTests {

    @Test func buildsTheRelativePathFromTheTrailingComponents() {
        let url = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/ABC/Library/Application Support/MusicBox/Downloads/artist-id/album-id/track-id.m4a")
        #expect(MusicLibrary.downloadRelativePath(for: url) == "MusicBox/Downloads/artist-id/album-id/track-id.m4a")
    }

    /// The same file reached through the unresolved path has to store the same thing.
    @Test func isUnaffectedByHowTheBasePathWasSpelled() {
        let resolved = URL(fileURLWithPath: "/private/var/app/Library/Application Support/MusicBox/Downloads/a/b/c.m4a")
        let unresolved = URL(fileURLWithPath: "/var/app/Library/Application Support/MusicBox/Downloads/a/b/c.m4a")
        #expect(MusicLibrary.downloadRelativePath(for: resolved)
                == MusicLibrary.downloadRelativePath(for: unresolved))
    }

    @Test func isNilForAPathTooShortToBeADownload() {
        #expect(MusicLibrary.downloadRelativePath(for: URL(fileURLWithPath: "/a.m4a")) == nil)
    }
}
