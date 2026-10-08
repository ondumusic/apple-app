import Foundation
import SwiftData
import Testing
@testable import Ondu

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
        lib.markDownloaded(trackId: t.id, relativePath: "Ondu/Downloads/x.m4a")
        #expect(lib.allTracks().first?.isDownloaded == true)
        lib.markUndownloaded(trackId: t.id)
        #expect(lib.allTracks().first?.isDownloaded == false)
    }
}

/// The background rebuild has to produce exactly what the synchronous path produces —
/// it's the same library read through a different context.
@Suite(.serialized)
struct BackgroundTrackCacheTests {

    private func makeLibrary() throws -> MusicLibrary {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: config
        )
        return MusicLibrary(container: container)
    }

    @Test func prepareMatchesSynchronousOrdering() async throws {
        let lib = try makeLibrary()
        let now = Date()
        let beatles = UUID(), radiohead = UUID()
        let revolver = UUID(), kida = UUID()
        lib.upsertArtists([
            SyncArtist(id: beatles, name: "The Beatles", sortName: "Beatles, The",
                       slug: "beatles", albumCount: 1, insertedAt: now),
            SyncArtist(id: radiohead, name: "Radiohead", sortName: "Radiohead",
                       slug: "radiohead", albumCount: 1, insertedAt: now),
        ])
        lib.upsertAlbums([
            SyncAlbum(id: revolver, artistId: beatles, name: "Revolver", sortName: "Revolver",
                      slug: "revolver", releaseYear: 1966, artworkUrl: nil, isUnknown: false,
                      trackCount: 2, insertedAt: now),
            SyncAlbum(id: kida, artistId: radiohead, name: "Kid A", sortName: "Kid A",
                      slug: "kid-a", releaseYear: 2000, artworkUrl: nil, isUnknown: false,
                      trackCount: 1, insertedAt: now),
        ])
        func track(_ name: String, artist: UUID, album: UUID, number: Int) -> SyncTrack {
            let id = UUID()
            return SyncTrack(id: id, artistId: artist, albumArtistId: artist, albumId: album,
                             name: name, disc: 1, number: number, duration: 200,
                             mimetype: "audio/mp4", streamUrl: "/s/\(id)",
                             downloadUrl: "/d/\(id)", insertedAt: now)
        }
        lib.upsertTracks([
            track("Idioteque", artist: radiohead, album: kida, number: 8),
            track("Taxman", artist: beatles, album: revolver, number: 1),
            track("Eleanor Rigby", artist: beatles, album: revolver, number: 2),
        ])
        lib.bumpRevision()

        let synchronous = lib.allTracks().map(\.name)
        lib.cachedAllTracks = nil
        await lib.prepareAllTracks()

        #expect(lib.cachedAllTracks?.map(\.name) == synchronous)
        #expect(synchronous == ["Taxman", "Eleanor Rigby", "Idioteque"])
    }

    @Test func prepareInstallsCacheForLaterSynchronousReads() async throws {
        let lib = try makeLibrary()
        await lib.prepareAllTracks()
        #expect(lib.cachedAllTracks != nil)
    }
}
