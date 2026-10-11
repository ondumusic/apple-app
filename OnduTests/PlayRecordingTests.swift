import Foundation
import SwiftData
import Testing

@testable import Ondu

@Suite
struct PlayThresholdTests {

    @Test func isHalfOfAShortTrack() {
        #expect(PlayerService.PlayThreshold.seconds(forDuration: 200) == 100)
    }

    /// A 20-minute side shouldn't need 10 minutes before it counts.
    @Test func capsLongTracksAtFourMinutes() {
        #expect(PlayerService.PlayThreshold.seconds(forDuration: 1200) == 240)
    }

    @Test func isExactlyTheCapAtTheCrossover() {
        #expect(PlayerService.PlayThreshold.seconds(forDuration: 480) == 240)
    }

    /// A stream whose length isn't known yet: fall back to the cap rather than treating
    /// zero as "half of nothing" and counting it immediately.
    @Test func fallsBackToTheCapWhenTheLengthIsUnknown() {
        #expect(PlayerService.PlayThreshold.seconds(forDuration: 0) == 240)
    }
}

@Suite
struct LocalPlayRecordingTests {

    private func makeLibrary() throws -> MusicLibrary {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
            LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return MusicLibrary(container: container)
    }

    @discardableResult
    private func seedTrack(_ lib: MusicLibrary, playCount: Int = 0, lastPlayedAt: Date? = nil) -> UUID {
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        let now = Date()
        lib.upsertArtists([
            SyncArtist(
                id: artistId, name: "Artist", sortName: "Artist",
                slug: "artist", albumCount: 1, insertedAt: now)
        ])
        lib.upsertAlbums([
            SyncAlbum(
                id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                slug: "album", releaseYear: nil, artworkUrl: nil,
                isUnknown: false, trackCount: 1, insertedAt: now)
        ])
        lib.upsertTracks([
            SyncTrack(
                id: trackId, artistId: artistId, albumArtistId: artistId,
                albumId: albumId, name: "Track", disc: 1, number: 1,
                duration: 200, mimetype: "audio/mp4", streamUrl: "/s/1",
                downloadUrl: "/d/1", insertedAt: now, lufs: nil,
                playCount: playCount, lastPlayedAt: lastPlayedAt)
        ])
        lib.bumpRevision()
        return trackId
    }

    @Test func countsThePlayLocally() throws {
        let lib = try makeLibrary()
        let trackId = seedTrack(lib, playCount: 4)
        let playedAt = Date(timeIntervalSince1970: 1_700_000_000)

        lib.recordLocalPlay(trackId: trackId, at: playedAt)

        let track = try #require(lib.track(trackId))
        #expect(track.playCount == 5)
        #expect(track.lastPlayedAt == playedAt)
    }

    /// The server counts plays from every device, so its total replaces ours rather than
    /// adding to it — otherwise this device's optimistic bump would be counted twice.
    @Test func theServersTotalReplacesTheLocalOne() throws {
        let lib = try makeLibrary()
        let trackId = seedTrack(lib, playCount: 4)
        lib.recordLocalPlay(trackId: trackId, at: Date())
        #expect(try #require(lib.track(trackId)).playCount == 5)

        let serverLastPlayed = Date(timeIntervalSince1970: 1_700_000_500)
        let existing = try #require(lib.track(trackId))
        lib.upsertTracks([
            SyncTrack(
                id: existing.id, artistId: existing.artistId,
                albumArtistId: existing.albumArtistId, albumId: existing.albumId,
                name: existing.name, disc: existing.disc, number: existing.number,
                duration: existing.duration, mimetype: existing.mimetype,
                streamUrl: existing.streamUrl, downloadUrl: existing.downloadUrl,
                insertedAt: Date(), lufs: nil,
                playCount: 9, lastPlayedAt: serverLastPlayed)
        ])
        lib.bumpRevision()

        let track = try #require(lib.track(trackId))
        #expect(track.playCount == 9)
        #expect(track.lastPlayedAt == serverLastPlayed)
    }

    @Test func ignoresATrackThatIsNotInTheLibrary() throws {
        let lib = try makeLibrary()
        lib.recordLocalPlay(trackId: UUID(), at: Date())
    }
}
