import Foundation
import SwiftData
import Testing
@testable import MusicBox

/// allTracks() sorts album-by-album rather than track-by-track. These pin the ordering
/// contract that optimisation has to keep, including the cases where an album's tracks
/// don't all share an album artist.
@Suite(.serialized)
struct AllTracksOrderingTests {

    private func makeLibrary() throws -> MusicLibrary {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: config
        )
        return MusicLibrary(container: container)
    }

    private let now = Date()

    private func artist(_ id: UUID, _ name: String, sort: String) -> SyncArtist {
        SyncArtist(id: id, name: name, sortName: sort, slug: name.lowercased(),
                   albumCount: 1, insertedAt: now)
    }

    private func album(_ id: UUID, artist: UUID, _ name: String, sort: String) -> SyncAlbum {
        SyncAlbum(id: id, artistId: artist, name: name, sortName: sort, slug: name.lowercased(),
                  releaseYear: 2000, artworkUrl: nil, isUnknown: false, trackCount: 1, insertedAt: now)
    }

    private func track(_ name: String, artist: UUID, albumArtist: UUID, album: UUID,
                       disc: Int = 1, number: Int) -> SyncTrack {
        let id = UUID()
        return SyncTrack(id: id, artistId: artist, albumArtistId: albumArtist, albumId: album,
                         name: name, disc: disc, number: number, duration: 200,
                         mimetype: "audio/mp4", streamUrl: "/stream/\(id)",
                         downloadUrl: "/download/\(id)", insertedAt: now)
    }

    @Test func sortsByAlbumArtistThenAlbumThenDiscThenNumber() throws {
        let lib = try makeLibrary()
        let beatles = UUID(), radiohead = UUID()
        let revolver = UUID(), abbey = UUID(), kida = UUID()
        lib.upsertArtists([artist(beatles, "The Beatles", sort: "Beatles, The"),
                           artist(radiohead, "Radiohead", sort: "Radiohead")])
        lib.upsertAlbums([album(revolver, artist: beatles, "Revolver", sort: "Revolver"),
                          album(abbey, artist: beatles, "Abbey Road", sort: "Abbey Road"),
                          album(kida, artist: radiohead, "Kid A", sort: "Kid A")])
        lib.upsertTracks([
            track("Idioteque", artist: radiohead, albumArtist: radiohead, album: kida, number: 8),
            track("Taxman", artist: beatles, albumArtist: beatles, album: revolver, disc: 2, number: 1),
            track("Eleanor Rigby", artist: beatles, albumArtist: beatles, album: revolver, disc: 1, number: 2),
            track("Yellow Submarine", artist: beatles, albumArtist: beatles, album: revolver, disc: 1, number: 1),
            track("Come Together", artist: beatles, albumArtist: beatles, album: abbey, number: 1),
        ])
        lib.bumpRevision()

        #expect(lib.allTracks().map(\.name) == [
            "Come Together",                                    // Beatles / Abbey Road
            "Yellow Submarine", "Eleanor Rigby", "Taxman",      // Beatles / Revolver, disc then number
            "Idioteque",                                        // Radiohead / Kid A
        ])
    }

    /// A compilation puts several album artists in one album; each keeps its own slot in
    /// the artist ordering rather than inheriting the first track's.
    @Test func splitsAnAlbumWhoseTracksHaveDifferentAlbumArtists() throws {
        let lib = try makeLibrary()
        let zoe = UUID(), adam = UUID(), various = UUID()
        let comp = UUID()
        lib.upsertArtists([artist(zoe, "Zoe", sort: "Zoe"),
                           artist(adam, "Adam", sort: "Adam"),
                           artist(various, "Various", sort: "Various")])
        lib.upsertAlbums([album(comp, artist: various, "Compilation", sort: "Compilation")])
        lib.upsertTracks([
            track("Zoe Song", artist: zoe, albumArtist: zoe, album: comp, number: 1),
            track("Adam Song", artist: adam, albumArtist: adam, album: comp, number: 2),
        ])
        lib.bumpRevision()

        #expect(lib.allTracks().map(\.name) == ["Adam Song", "Zoe Song"])
    }

    @Test func cachedResultReflectsDownloadStateChanges() throws {
        let lib = try makeLibrary()
        let a = UUID(), alb = UUID()
        lib.upsertArtists([artist(a, "Artist", sort: "Artist")])
        lib.upsertAlbums([album(alb, artist: a, "Album", sort: "Album")])
        let t = track("Song", artist: a, albumArtist: a, album: alb, number: 1)
        lib.upsertTracks([t])
        lib.bumpRevision()

        #expect(lib.allTracks().first?.isDownloaded == false)
        lib.markDownloaded(trackId: t.id, relativePath: "MusicBox/Downloads/x.m4a")
        #expect(lib.allTracks().first?.isDownloaded == true)
        lib.markUndownloaded(trackId: t.id)
        #expect(lib.allTracks().first?.isDownloaded == false)
    }
}
