import Foundation
import SwiftData
import Testing
@testable import MusicBox

private func dB(_ gain: Float) -> Double { 20 * log10(Double(gain)) }

@Suite
struct LoudnessGainTests {

    @Test func bringsALoudMasterDownToTheTarget() {
        // -9 LUFS is a typical modern master: 5 dB above the -14 target.
        #expect(dB(LoudnessNormalization.gain(forLUFS: -9)).isApproximately(-5))
    }

    @Test func leavesATrackAtTheTargetAlone() {
        #expect(LoudnessNormalization.gain(forLUFS: LoudnessNormalization.targetLUFS) == 1)
    }

    /// We have no headroom above unity, so a track quieter than the target can't be
    /// lifted to meet it.
    @Test func doesNotBoostATrackBelowTheTarget() {
        #expect(LoudnessNormalization.gain(forLUFS: -24) == 1)
    }

    @Test func leavesAnUnmeasuredTrackAlone() {
        #expect(LoudnessNormalization.gain(forLUFS: nil) == 1)
    }

    /// Album gain is one offset for the whole record, so the gap between a quiet track
    /// and a loud one survives it — that's the difference from track gain, and the reason
    /// album mode exists.
    @Test func albumGainPreservesTheGapBetweenTracks() {
        let albumGain = LoudnessNormalization.gain(forLUFS: -10)

        let quietUnderAlbumGain = dB(albumGain) + (-20)
        let loudUnderAlbumGain = dB(albumGain) + (-8)
        #expect((loudUnderAlbumGain - quietUnderAlbumGain).isApproximately(12))

        // Track gain would have closed that gap to the 6 dB the clamp leaves behind:
        // -20 is under the target, so it can't be lifted to meet the other.
        let quietUnderTrackGain = dB(LoudnessNormalization.gain(forLUFS: -20)) + (-20)
        let loudUnderTrackGain = dB(LoudnessNormalization.gain(forLUFS: -8)) + (-8)
        #expect((loudUnderTrackGain - quietUnderTrackGain).isApproximately(6))
    }
}

private extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.01) -> Bool {
        abs(self - other) < tolerance
    }
}

// MARK: - Album loudness through the library

@Suite
struct MusicLibraryAlbumLoudnessTests {

    private func makeLibrary() throws -> MusicLibrary {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return MusicLibrary(container: container)
    }

    /// Seeds one album, with the loudness the server would have sent for it.
    @discardableResult
    private func seed(_ lib: MusicLibrary, albumLUFS: Double?) -> UUID {
        let artistId = UUID()
        let albumId = UUID()
        let now = Date()
        lib.upsertArtists([SyncArtist(id: artistId, name: "Artist", sortName: "Artist",
                                      slug: "artist", albumCount: 1, insertedAt: now)])
        lib.upsertAlbums([SyncAlbum(id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                                    slug: "album", releaseYear: nil, artworkUrl: nil,
                                    isUnknown: false, trackCount: 2, insertedAt: now,
                                    lufs: albumLUFS)])
        lib.bumpRevision()
        return albumId
    }

    @Test func takesTheLevelTheServerMeasured() throws {
        let lib = try makeLibrary()
        let albumId = seed(lib, albumLUFS: -10)

        #expect(try #require(lib.albumLUFS(for: albumId)).isApproximately(-10))
    }

    @Test func isNilUntilTheServerHasMeasuredIt() throws {
        let lib = try makeLibrary()
        let albumId = seed(lib, albumLUFS: nil)

        #expect(lib.albumLUFS(for: albumId) == nil)
    }

    @Test func isNilForAnAlbumThatIsNotInTheLibrary() throws {
        #expect(try makeLibrary().albumLUFS(for: UUID()) == nil)
    }

    /// Queries read the revision counter every mutation bumps; without that a re-scan's
    /// new values would never reach playback.
    @Test func picksUpNewValuesAfterASync() throws {
        let lib = try makeLibrary()
        let albumId = seed(lib, albumLUFS: nil)
        #expect(lib.albumLUFS(for: albumId) == nil)

        let album = try #require(lib.album(albumId))
        lib.upsertAlbums([SyncAlbum(id: album.id, artistId: album.artistId, name: album.name,
                                    sortName: album.sortName, slug: album.slug,
                                    releaseYear: album.releaseYear, artworkUrl: album.artworkUrl,
                                    isUnknown: album.isUnknown, trackCount: 2,
                                    insertedAt: Date(), lufs: -12)])
        lib.bumpRevision()

        #expect(try #require(lib.albumLUFS(for: albumId)).isApproximately(-12))
    }
}
