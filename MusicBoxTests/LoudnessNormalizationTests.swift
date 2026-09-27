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
}

@Suite
struct AlbumLoudnessTests {

    @Test func matchesTheTrackValueWhenEveryTrackIsTheSame() {
        let tracks: [(lufs: Double?, duration: Double)] = [(-10, 200), (-10, 300), (-10, 150)]
        #expect(LoudnessNormalization.albumLUFS(tracks)!.isApproximately(-10))
    }

    /// A mean of energy, not of decibels: a long loud track should pull the album further
    /// than a short quiet one. The dB average of -6 and -20 is -13; the energy average is
    /// dominated by the louder, longer track.
    @Test func weightsByEnergyAndDuration() {
        let tracks: [(lufs: Double?, duration: Double)] = [(-6, 400), (-20, 100)]
        let album = LoudnessNormalization.albumLUFS(tracks)!
        #expect(album > -8)
        #expect(album < -6)
    }

    @Test func ignoresUnmeasuredTracks() {
        let measured: [(lufs: Double?, duration: Double)] = [(-12, 200), (-12, 200)]
        let mixed: [(lufs: Double?, duration: Double)] = [(-12, 200), (nil, 200), (-12, 200)]
        #expect(LoudnessNormalization.albumLUFS(mixed)! == LoudnessNormalization.albumLUFS(measured)!)
    }

    @Test func isNilWhenNothingIsMeasured() {
        let tracks: [(lufs: Double?, duration: Double)] = [(nil, 200), (nil, 300)]
        #expect(LoudnessNormalization.albumLUFS(tracks) == nil)
    }

    @Test func isNilForAnEmptyAlbum() {
        #expect(LoudnessNormalization.albumLUFS([]) == nil)
    }

    /// Album gain is one offset for the whole record, so the gap between a quiet track
    /// and a loud one survives it — that's the difference from track gain, and the reason
    /// album mode exists.
    @Test func preservesTheGapBetweenTracksOnAnAlbum() {
        let tracks: [(lufs: Double?, duration: Double)] = [(-20, 120), (-8, 240)]
        let albumGain = LoudnessNormalization.gain(forLUFS: LoudnessNormalization.albumLUFS(tracks))

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

// MARK: - Derivation through the library

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

    /// Seeds one album whose tracks carry the given loudness values.
    @discardableResult
    private func seed(_ lib: MusicLibrary, lufs: [Double?], duration: Double = 200) -> UUID {
        let artistId = UUID()
        let albumId = UUID()
        let now = Date()
        lib.upsertArtists([SyncArtist(id: artistId, name: "Artist", sortName: "Artist",
                                      slug: "artist", albumCount: 1, insertedAt: now)])
        lib.upsertAlbums([SyncAlbum(id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                                    slug: "album", releaseYear: nil, artworkUrl: nil,
                                    isUnknown: false, trackCount: lufs.count, insertedAt: now)])
        lib.upsertTracks(lufs.enumerated().map { index, value in
            SyncTrack(id: UUID(), artistId: artistId, albumArtistId: artistId, albumId: albumId,
                      name: "Track \(index)", disc: 1, number: index + 1, duration: duration,
                      mimetype: "audio/mp4", streamUrl: "/stream/\(index)",
                      downloadUrl: "/download/\(index)", insertedAt: now, lufs: value)
        })
        lib.bumpRevision()
        return albumId
    }

    @Test func derivesTheAlbumLevelFromItsTracks() throws {
        let lib = try makeLibrary()
        let albumId = seed(lib, lufs: [-10, -10, -10])

        #expect(abs(try #require(lib.albumLUFS(for: albumId)) - (-10)) < 0.01)
    }

    @Test func isNilForAnAlbumNothingHasMeasured() throws {
        let lib = try makeLibrary()
        let albumId = seed(lib, lufs: [nil, nil])

        #expect(lib.albumLUFS(for: albumId) == nil)
    }

    @Test func isNilForAnAlbumThatIsNotInTheLibrary() throws {
        #expect(try makeLibrary().albumLUFS(for: UUID()) == nil)
    }

    /// The cache is keyed by album and cleared on the revision bump every mutation makes;
    /// without that a re-scan's new values would never reach playback.
    @Test func picksUpNewValuesAfterASync() throws {
        let lib = try makeLibrary()
        let albumId = seed(lib, lufs: [nil, nil])
        #expect(lib.albumLUFS(for: albumId) == nil)

        let tracks = lib.tracksForAlbum(albumId)
        lib.upsertTracks(tracks.map { track in
            SyncTrack(id: track.id, artistId: track.artistId, albumArtistId: track.albumArtistId,
                      albumId: track.albumId, name: track.name, disc: track.disc,
                      number: track.number, duration: track.duration, mimetype: track.mimetype,
                      streamUrl: track.streamUrl, downloadUrl: track.downloadUrl,
                      insertedAt: Date(), lufs: -12)
        })
        lib.bumpRevision()

        #expect(abs(try #require(lib.albumLUFS(for: albumId)) - (-12)) < 0.01)
    }
}
