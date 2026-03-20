import Foundation
import SwiftData
import Testing
@testable import MusicBox

// MARK: - Helpers

private func makeTestLibrary() throws -> MusicLibrary {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
        configurations: config
    )
    return MusicLibrary(container: container)
}

private let now = Date()

private func syncArtist(id: UUID = UUID(), name: String, sortName: String? = nil,
                        slug: String? = nil, albumCount: Int = 1) -> SyncArtist {
    SyncArtist(id: id, name: name, sortName: sortName ?? name, slug: slug ?? name.lowercased(),
               albumCount: albumCount, insertedAt: now)
}

private func syncAlbum(id: UUID = UUID(), artistId: UUID, name: String, sortName: String? = nil,
                       slug: String? = nil, releaseYear: Int? = nil, trackCount: Int = 1,
                       isUnknown: Bool = false) -> SyncAlbum {
    SyncAlbum(id: id, artistId: artistId, name: name, sortName: sortName ?? name,
              slug: slug ?? name.lowercased(), releaseYear: releaseYear,
              artworkUrl: nil, isUnknown: isUnknown, trackCount: trackCount, insertedAt: now)
}

private func syncTrack(id: UUID = UUID(), artistId: UUID, albumArtistId: UUID? = nil,
                       albumId: UUID, name: String, disc: Int = 1, number: Int = 1,
                       duration: Double = 200, mimetype: String = "audio/mp4",
                       fileSize: Int64 = 5_000_000) -> SyncTrack {
    SyncTrack(id: id, artistId: artistId, albumArtistId: albumArtistId ?? artistId,
              albumId: albumId, name: name, disc: disc, number: number,
              duration: duration, mimetype: mimetype,
              streamUrl: "/stream/\(id)", downloadUrl: "/download/\(id)",
              insertedAt: now,
              file: SyncTrack.SyncFile(size: fileSize, checksum: "abc123"))
}

// MARK: - Artist Query Tests

@Suite(.serialized)
struct MusicLibraryArtistTests {

    @Test func allArtistsReturnsSortedByName() throws {
        let lib = try makeTestLibrary()
        let a1 = syncArtist(name: "Radiohead", sortName: "Radiohead")
        let a2 = syncArtist(name: "The Beatles", sortName: "Beatles, The")
        lib.upsertArtists([a1, a2])
        lib.bumpRevision()

        let artists = lib.allArtists()
        #expect(artists.count == 2)
        #expect(artists[0].sortName == "Beatles, The")
        #expect(artists[1].sortName == "Radiohead")
    }

    @Test func allArtistsExcludesZeroAlbums() throws {
        let lib = try makeTestLibrary()
        let a1 = syncArtist(name: "Has Albums", albumCount: 2)
        let a2 = syncArtist(name: "No Albums", albumCount: 0)
        lib.upsertArtists([a1, a2])
        lib.bumpRevision()

        let artists = lib.allArtists()
        #expect(artists.count == 1)
        #expect(artists[0].name == "Has Albums")
    }

    @Test func artistLookupById() throws {
        let lib = try makeTestLibrary()
        let id = UUID()
        lib.upsertArtists([syncArtist(id: id, name: "Bjork")])
        lib.bumpRevision()

        let artist = lib.artist(id)
        #expect(artist?.name == "Bjork")
        #expect(lib.artist(UUID()) == nil)
    }
}

// MARK: - Album Query Tests

@Suite(.serialized)
struct MusicLibraryAlbumTests {

    @Test func allAlbumsExcludesZeroTracks() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        let a1 = syncAlbum(artistId: artistId, name: "With Tracks", trackCount: 5)
        let a2 = syncAlbum(artistId: artistId, name: "Empty", trackCount: 0)
        lib.upsertAlbums([a1, a2])
        lib.bumpRevision()

        let albums = lib.allAlbums()
        #expect(albums.count == 1)
        #expect(albums[0].name == "With Tracks")
    }

    @Test func albumsForArtistSortedByReleaseYearDescending() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        let a1 = syncAlbum(artistId: artistId, name: "Old", releaseYear: 1990)
        let a2 = syncAlbum(artistId: artistId, name: "New", releaseYear: 2020)
        let a3 = syncAlbum(artistId: artistId, name: "Mid", releaseYear: 2005)
        lib.upsertAlbums([a1, a2, a3])
        lib.bumpRevision()

        let albums = lib.albumsForArtist(artistId)
        #expect(albums.count == 3)
        #expect(albums[0].name == "New")
        #expect(albums[1].name == "Mid")
        #expect(albums[2].name == "Old")
    }

    @Test func albumLookupById() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.bumpRevision()

        #expect(lib.album(albumId)?.name == "Album")
        #expect(lib.album(UUID()) == nil)
    }

    @Test func allAlbumsIncludesArtistInfo() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Pink Floyd", sortName: "Pink Floyd")])
        lib.upsertAlbums([syncAlbum(artistId: artistId, name: "The Wall")])
        lib.bumpRevision()

        let albums = lib.allAlbums()
        #expect(albums.count == 1)
        #expect(albums[0].artistName == "Pink Floyd")
        #expect(albums[0].artistSortName == "Pink Floyd")
    }

    @Test func albumsForArtistNilYearSortsLast() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([
            syncAlbum(artistId: artistId, name: "With Year", releaseYear: 2020),
            syncAlbum(artistId: artistId, name: "No Year", releaseYear: nil),
        ])
        lib.bumpRevision()

        let albums = lib.albumsForArtist(artistId)
        #expect(albums[0].name == "With Year")
        #expect(albums[1].name == "No Year")
    }

    @Test func albumsForArtistDoesNotReturnOtherArtists() throws {
        let lib = try makeTestLibrary()
        let a1 = UUID(), a2 = UUID()
        lib.upsertArtists([
            syncArtist(id: a1, name: "Artist 1"),
            syncArtist(id: a2, name: "Artist 2"),
        ])
        lib.upsertAlbums([
            syncAlbum(artistId: a1, name: "A1 Album"),
            syncAlbum(artistId: a2, name: "A2 Album"),
        ])
        lib.bumpRevision()

        let albums = lib.albumsForArtist(a1)
        #expect(albums.count == 1)
        #expect(albums[0].name == "A1 Album")
    }
}

// MARK: - Track Query Tests

@Suite(.serialized)
struct MusicLibraryTrackTests {

    @Test func tracksForAlbumSortedByDiscAndNumber() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 4)])

        let t1 = syncTrack(artistId: artistId, albumId: albumId, name: "D2T1", disc: 2, number: 1)
        let t2 = syncTrack(artistId: artistId, albumId: albumId, name: "D1T2", disc: 1, number: 2)
        let t3 = syncTrack(artistId: artistId, albumId: albumId, name: "D1T1", disc: 1, number: 1)
        let t4 = syncTrack(artistId: artistId, albumId: albumId, name: "D2T2", disc: 2, number: 2)
        lib.upsertTracks([t1, t2, t3, t4])
        lib.bumpRevision()

        let tracks = lib.tracksForAlbum(albumId)
        #expect(tracks.map(\.name) == ["D1T1", "D1T2", "D2T1", "D2T2"])
    }

    @Test func trackLookupById() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])
        lib.bumpRevision()

        let track = lib.track(trackId)
        #expect(track?.name == "Song")
        #expect(track?.artist.name == "Artist")
        #expect(lib.track(UUID()) == nil)
    }

    @Test func allTracksSortedByArtistAlbumDiscNumber() throws {
        let lib = try makeTestLibrary()
        let artist1 = UUID()
        let artist2 = UUID()
        let album1 = UUID()
        let album2 = UUID()
        lib.upsertArtists([
            syncArtist(id: artist1, name: "Zeppelin", sortName: "Zeppelin"),
            syncArtist(id: artist2, name: "ABBA", sortName: "ABBA"),
        ])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: artist1, name: "IV", sortName: "IV"),
            syncAlbum(id: album2, artistId: artist2, name: "Gold", sortName: "Gold"),
        ])
        lib.upsertTracks([
            syncTrack(artistId: artist1, albumId: album1, name: "Stairway", disc: 1, number: 1),
            syncTrack(artistId: artist2, albumId: album2, name: "Dancing Queen", disc: 1, number: 1),
        ])
        lib.bumpRevision()

        let tracks = lib.allTracks()
        #expect(tracks.count == 2)
        // ABBA sorts before Zeppelin
        #expect(tracks[0].name == "Dancing Queen")
        #expect(tracks[1].name == "Stairway")
    }

    @Test func allTracksSortByAlbumThenDiscThenNumber() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let album1 = UUID()
        let album2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist", sortName: "Artist")])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: artistId, name: "B Album", sortName: "B Album", trackCount: 3),
            syncAlbum(id: album2, artistId: artistId, name: "A Album", sortName: "A Album", trackCount: 2),
        ])
        lib.upsertTracks([
            syncTrack(artistId: artistId, albumId: album1, name: "B-D1T2", disc: 1, number: 2),
            syncTrack(artistId: artistId, albumId: album1, name: "B-D1T1", disc: 1, number: 1),
            syncTrack(artistId: artistId, albumId: album1, name: "B-D2T1", disc: 2, number: 1),
            syncTrack(artistId: artistId, albumId: album2, name: "A-T1", disc: 1, number: 1),
            syncTrack(artistId: artistId, albumId: album2, name: "A-T2", disc: 1, number: 2),
        ])
        lib.bumpRevision()

        let tracks = lib.allTracks()
        // Same artist → sorted by album sortName, then disc, then number
        #expect(tracks.map(\.name) == ["A-T1", "A-T2", "B-D1T1", "B-D1T2", "B-D2T1"])
    }

    @Test func trackIncludesArtistAndAlbumInfo() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Pink Floyd", sortName: "Pink Floyd", slug: "pink-floyd")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "The Wall", sortName: "Wall, The")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Comfortably Numb",
                                    disc: 2, number: 6, duration: 382, mimetype: "audio/flac")])
        lib.bumpRevision()

        let track = lib.track(trackId)!
        #expect(track.artist.name == "Pink Floyd")
        #expect(track.artist.slug == "pink-floyd")
        #expect(track.album?.name == "The Wall")
        #expect(track.disc == 2)
        #expect(track.number == 6)
        #expect(track.duration == 382)
        #expect(track.mimetype == "audio/flac")
        #expect(track.albumArtistSortName == "Pink Floyd")
    }

    @Test func trackWithDifferentArtistAndAlbumArtist() throws {
        let lib = try makeTestLibrary()
        let albumArtistId = UUID()
        let trackArtistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([
            syncArtist(id: albumArtistId, name: "Various Artists", sortName: "Various Artists"),
            syncArtist(id: trackArtistId, name: "Featured Artist", sortName: "Featured Artist"),
        ])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: albumArtistId, name: "Compilation")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: trackArtistId, albumArtistId: albumArtistId,
                                    albumId: albumId, name: "Featured Song")])
        lib.bumpRevision()

        let track = lib.track(trackId)!
        #expect(track.artist.name == "Featured Artist")
        #expect(track.albumArtistSortName == "Various Artists")
        #expect(track.artistId == trackArtistId)
        #expect(track.albumArtistId == albumArtistId)
    }
}

// MARK: - Upsert Tests

@Suite(.serialized)
struct MusicLibraryUpsertTests {

    @Test func upsertArtistUpdatesExisting() throws {
        let lib = try makeTestLibrary()
        let id = UUID()
        lib.upsertArtists([syncArtist(id: id, name: "Old Name")])
        lib.upsertArtists([syncArtist(id: id, name: "New Name")])
        lib.bumpRevision()

        let artists = lib.allArtists()
        #expect(artists.count == 1)
        #expect(artists[0].name == "New Name")
    }

    @Test func upsertAlbumUpdatesExisting() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "V1", releaseYear: 2000)])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "V2", releaseYear: 2024)])
        lib.bumpRevision()

        let album = lib.album(albumId)
        #expect(album?.name == "V2")
        #expect(album?.releaseYear == 2024)
    }

    @Test func upsertAlbumReturnsNewlyInsertedIds() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId1 = UUID()
        let albumId2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])

        let inserted1 = lib.upsertAlbums([syncAlbum(id: albumId1, artistId: artistId, name: "A1")])
        #expect(inserted1 == [albumId1])

        // Second upsert of same album: not newly inserted
        let inserted2 = lib.upsertAlbums([
            syncAlbum(id: albumId1, artistId: artistId, name: "A1 Updated"),
            syncAlbum(id: albumId2, artistId: artistId, name: "A2"),
        ])
        #expect(inserted2 == [albumId2])
    }

    @Test func upsertEmptyArrayIsNoop() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([])
        lib.upsertAlbums([])
        lib.upsertTracks([])
        lib.bumpRevision()

        #expect(lib.allArtists().isEmpty)
        #expect(lib.allAlbums().isEmpty)
        #expect(lib.allTracks().isEmpty)
    }

    @Test func upsertTrackUpdatesExisting() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "V1")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "V2")])
        lib.bumpRevision()

        let track = lib.track(trackId)
        #expect(track?.name == "V2")
    }
}

// MARK: - Download State Tests

@Suite(.serialized)
struct MusicLibraryDownloadTests {

    @Test func markDownloadedAndQuery() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])

        #expect(!lib.isDownloaded(trackId: trackId))

        lib.markDownloaded(trackId: trackId, relativePath: "MusicBox/Downloads/a/b/c.m4a", downloadedFileSize: 1234)

        #expect(lib.isDownloaded(trackId: trackId))
    }

    @Test func markUndownloaded() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])

        lib.markDownloaded(trackId: trackId, relativePath: "path.m4a")
        lib.markUndownloaded(trackId: trackId)

        #expect(!lib.isDownloaded(trackId: trackId))
    }

    @Test func downloadedTrackCount() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID(), t2 = UUID(), t3 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 3)])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", number: 1),
            syncTrack(id: t2, artistId: artistId, albumId: albumId, name: "S2", number: 2),
            syncTrack(id: t3, artistId: artistId, albumId: albumId, name: "S3", number: 3),
        ])

        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")
        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a")

        #expect(lib.downloadedTrackCount(albumId: albumId) == 2)
    }

    @Test func isAlbumFullyDownloaded() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", number: 1),
            syncTrack(id: t2, artistId: artistId, albumId: albumId, name: "S2", number: 2),
        ])

        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")
        #expect(!lib.isAlbumFullyDownloaded(albumId: albumId))

        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a")
        #expect(lib.isAlbumFullyDownloaded(albumId: albumId))
    }

    @Test func isArtistDownloadedAndFullyDownloaded() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1")])

        #expect(!lib.isArtistDownloaded(artistId: artistId))
        lib.markDownloaded(trackId: t1, relativePath: "p.m4a")
        #expect(lib.isArtistDownloaded(artistId: artistId))
        #expect(lib.isArtistFullyDownloaded(artistId: artistId))
    }

    @Test func downloadedArtistsReturnsSortedArtistsWithDownloads() throws {
        let lib = try makeTestLibrary()
        let a1 = UUID(), a2 = UUID(), a3 = UUID()
        let album1 = UUID(), album2 = UUID(), album3 = UUID()
        let t1 = UUID(), t2 = UUID(), t3 = UUID()
        lib.upsertArtists([
            syncArtist(id: a1, name: "Zed", sortName: "Zed"),
            syncArtist(id: a2, name: "Alpha", sortName: "Alpha"),
            syncArtist(id: a3, name: "No Downloads", sortName: "No Downloads"),
        ])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: a1, name: "Z Album"),
            syncAlbum(id: album2, artistId: a2, name: "A Album"),
            syncAlbum(id: album3, artistId: a3, name: "N Album"),
        ])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: a1, albumId: album1, name: "ZT"),
            syncTrack(id: t2, artistId: a2, albumId: album2, name: "AT"),
            syncTrack(id: t3, artistId: a3, albumId: album3, name: "NT"),
        ])

        lib.markDownloaded(trackId: t1, relativePath: "z.m4a")
        lib.markDownloaded(trackId: t2, relativePath: "a.m4a")

        let downloaded = lib.downloadedArtists()
        #expect(downloaded.count == 2)
        #expect(downloaded[0].name == "Alpha")
        #expect(downloaded[1].name == "Zed")
    }

    @Test func downloadedSizeAggregates() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", number: 1, fileSize: 1000),
            syncTrack(id: t2, artistId: artistId, albumId: albumId, name: "S2", number: 2, fileSize: 2000),
        ])

        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a", downloadedFileSize: 1500)
        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a", downloadedFileSize: 2500)

        // downloadedFileSize is used when > 0
        #expect(lib.downloadedSize() == 4000)
        #expect(lib.downloadedSize(artistId: artistId) == 4000)
    }

    @Test func downloadedSizeFallsBackToFileSize() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", fileSize: 3000)])

        // downloadedFileSize defaults to 0, so falls back to fileSize
        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")

        #expect(lib.downloadedSize() == 3000)
    }

    @Test func downloadChangedTracksIds() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", number: 1),
            syncTrack(id: t2, artistId: artistId, albumId: albumId, name: "S2", number: 2),
        ])

        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")
        #expect(lib.downloadChanged.contains(t1))

        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a")
        #expect(lib.downloadChanged.contains(t2))
    }

    @Test func applyDownloadChangesUpdatesTracksInPlace() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])
        lib.bumpRevision()

        var tracks = lib.tracksForAlbum(albumId)
        #expect(!tracks[0].isDownloaded)

        lib.markDownloaded(trackId: trackId, relativePath: "p.m4a")
        lib.applyDownloadChanges(to: &tracks)

        #expect(tracks[0].isDownloaded)
    }

    @Test func markAllUndownloaded() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", number: 1),
            syncTrack(id: t2, artistId: artistId, albumId: albumId, name: "S2", number: 2),
        ])

        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")
        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a")
        lib.markAllUndownloaded()

        #expect(!lib.isDownloaded(trackId: t1))
        #expect(!lib.isDownloaded(trackId: t2))
        #expect(lib.downloadedSize() == 0)
    }
}

// MARK: - Deletion Tests

@Suite(.serialized)
struct MusicLibraryDeletionTests {

    @Test func deleteTrack() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "track", entityId: trackId)])
        lib.bumpRevision()

        #expect(lib.track(trackId) == nil)
    }

    @Test func deleteAlbumCascadesTracks() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "album", entityId: albumId)])
        lib.bumpRevision()

        #expect(lib.album(albumId) == nil)
        #expect(lib.track(trackId) == nil)
    }

    @Test func deleteArtistCascadesAlbumsAndTracks() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Song")])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "artist", entityId: artistId)])
        lib.bumpRevision()

        #expect(lib.artist(artistId) == nil)
        #expect(lib.album(albumId) == nil)
        #expect(lib.track(trackId) == nil)
    }

    @Test func clearAllRemovesEverything() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(artistId: artistId, albumId: albumId, name: "Song")])
        lib.bumpRevision()

        lib.clearAll()

        #expect(lib.allArtists().isEmpty)
        #expect(lib.allAlbums().isEmpty)
        #expect(lib.allTracks().isEmpty)
    }
}

// MARK: - Revision Counter Tests

@Suite(.serialized)
struct MusicLibraryRevisionTests {

    @Test func revisionStartsAtZero() throws {
        let lib = try makeTestLibrary()
        #expect(lib.revision == 0)
    }

    @Test func bumpRevisionIncrements() throws {
        let lib = try makeTestLibrary()
        lib.bumpRevision()
        #expect(lib.revision == 1)
        lib.bumpRevision()
        #expect(lib.revision == 2)
    }

    @Test func clearAllIncrementsRevision() throws {
        let lib = try makeTestLibrary()
        lib.clearAll()
        #expect(lib.revision == 1)
    }
}

// MARK: - Search Tests

@Suite(.serialized)
struct MusicLibrarySearchTests {

    @Test func searchFindsArtistsByName() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([
            syncArtist(name: "The Beatles", sortName: "Beatles, The"),
            syncArtist(name: "Radiohead"),
        ])
        lib.bumpRevision()

        let results = lib.search("beatles")
        #expect(results.artists.count == 1)
        #expect(results.artists[0].name == "The Beatles")
    }

    @Test func searchFindsAlbumsByName() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([
            syncAlbum(artistId: artistId, name: "Abbey Road"),
            syncAlbum(artistId: artistId, name: "OK Computer"),
        ])
        lib.bumpRevision()

        let results = lib.search("abbey")
        #expect(results.albums.count == 1)
        #expect(results.albums[0].name == "Abbey Road")
    }

    @Test func searchFindsTracksByName() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([
            syncTrack(artistId: artistId, albumId: albumId, name: "Stairway to Heaven"),
            syncTrack(artistId: artistId, albumId: albumId, name: "Black Dog", number: 2),
        ])
        lib.bumpRevision()

        let results = lib.search("stairway")
        #expect(results.tracks.count == 1)
        #expect(results.tracks[0].name == "Stairway to Heaven")
    }

    @Test func searchEmptyQueryReturnsEmpty() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([syncArtist(name: "Artist")])
        lib.bumpRevision()

        let results = lib.search("")
        #expect(results.artists.isEmpty)
        #expect(results.albums.isEmpty)
        #expect(results.tracks.isEmpty)
    }

    @Test func searchExcludesArtistsWithZeroAlbums() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([syncArtist(name: "Ghost Artist", albumCount: 0)])
        lib.bumpRevision()

        let results = lib.search("ghost")
        #expect(results.artists.isEmpty)
    }

    @Test func searchExcludesAlbumsWithZeroTracks() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(artistId: artistId, name: "Empty Album", trackCount: 0)])
        lib.bumpRevision()

        let results = lib.search("empty")
        #expect(results.albums.isEmpty)
    }

    @Test func searchIsCaseInsensitive() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([syncArtist(name: "Radiohead")])
        lib.bumpRevision()

        #expect(lib.search("radiohead").artists.count == 1)
        #expect(lib.search("RADIOHEAD").artists.count == 1)
        #expect(lib.search("RadioHead").artists.count == 1)
    }

    @Test func searchMatchesSortName() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([syncArtist(name: "The Beatles", sortName: "Beatles, The")])
        lib.bumpRevision()

        // Should match on sortName too
        let results = lib.search("beatles")
        #expect(results.artists.count == 1)
    }

    @Test func searchArtistsSortedBySortName() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([
            syncArtist(name: "Zeppelin", sortName: "Zeppelin"),
            syncArtist(name: "The Beatles", sortName: "Beatles, The"),
            syncArtist(name: "ABBA", sortName: "ABBA"),
        ])
        lib.bumpRevision()

        // Search for something that matches all — use a very broad term
        // Each has unique names, so search for partial match on common letter
        let all = lib.allArtists()
        #expect(all[0].sortName == "ABBA")
        #expect(all[1].sortName == "Beatles, The")
        #expect(all[2].sortName == "Zeppelin")
    }

    @Test func searchReturnsMultipleEntityTypes() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Blue Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Blue Album")])
        lib.upsertTracks([syncTrack(artistId: artistId, albumId: albumId, name: "Blue Song")])
        lib.bumpRevision()

        let results = lib.search("blue")
        #expect(results.artists.count == 1)
        #expect(results.albums.count == 1)
        #expect(results.tracks.count == 1)
    }

    @Test func searchNoMatch() throws {
        let lib = try makeTestLibrary()
        lib.upsertArtists([syncArtist(name: "Radiohead")])
        lib.bumpRevision()

        let results = lib.search("zzzznonexistent")
        #expect(results.artists.isEmpty)
        #expect(results.albums.isEmpty)
        #expect(results.tracks.isEmpty)
    }
}

// MARK: - Additional Query Tests

@Suite(.serialized)
struct MusicLibraryAdditionalQueryTests {

    @Test func albumWithTracksIncludesTracks() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(artistId: artistId, albumId: albumId, name: "T1", number: 1),
            syncTrack(artistId: artistId, albumId: albumId, name: "T2", number: 2),
        ])
        lib.bumpRevision()

        let album = lib.albumWithTracks(albumId)
        #expect(album?.name == "Album")
        #expect(album?.tracks?.count == 2)
        #expect(album?.tracks?[0].name == "T1")
    }

    @Test func albumsWithTracksForArtist() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let album1 = UUID(), album2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: artistId, name: "A1", releaseYear: 2020, trackCount: 1),
            syncAlbum(id: album2, artistId: artistId, name: "A2", releaseYear: 2010, trackCount: 1),
        ])
        lib.upsertTracks([
            syncTrack(artistId: artistId, albumId: album1, name: "T1"),
            syncTrack(artistId: artistId, albumId: album2, name: "T2"),
        ])
        lib.bumpRevision()

        let albums = lib.albumsWithTracksForArtist(artistId)
        #expect(albums.count == 2)
        // Sorted by release year descending
        #expect(albums[0].name == "A1")
        #expect(albums[0].tracks?.count == 1)
        #expect(albums[1].name == "A2")
    }

    @Test func albumsWithTracksForArtistSortsByDiscNumber() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Double Album", trackCount: 4)])
        lib.upsertTracks([
            syncTrack(artistId: artistId, albumId: albumId, name: "D2T1", disc: 2, number: 1),
            syncTrack(artistId: artistId, albumId: albumId, name: "D1T2", disc: 1, number: 2),
            syncTrack(artistId: artistId, albumId: albumId, name: "D1T1", disc: 1, number: 1),
            syncTrack(artistId: artistId, albumId: albumId, name: "D2T2", disc: 2, number: 2),
        ])
        lib.bumpRevision()

        let albums = lib.albumsWithTracksForArtist(artistId)
        #expect(albums.count == 1)
        #expect(albums[0].tracks?.map(\.name) == ["D1T1", "D1T2", "D2T1", "D2T2"])
    }

    @Test func albumsWithTracksForArtistIncludesFeaturedTracks() throws {
        let lib = try makeTestLibrary()
        let albumArtist = UUID()
        let featuredArtist = UUID()
        let albumId = UUID()
        lib.upsertArtists([
            syncArtist(id: albumArtist, name: "Main Artist"),
            syncArtist(id: featuredArtist, name: "Featured"),
        ])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: albumArtist, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(artistId: albumArtist, albumArtistId: albumArtist, albumId: albumId, name: "Solo Track", number: 1),
            syncTrack(artistId: featuredArtist, albumArtistId: albumArtist, albumId: albumId, name: "Feat Track", number: 2),
        ])
        lib.bumpRevision()

        let albums = lib.albumsWithTracksForArtist(albumArtist)
        #expect(albums.count == 1)
        #expect(albums[0].tracks?.count == 2)
        // Featured track should show its own artist
        let featTrack = albums[0].tracks?.first(where: { $0.name == "Feat Track" })
        #expect(featTrack?.artist.name == "Featured")
    }

    @Test func cachedMapsInvalidatedOnBumpRevision() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.bumpRevision()

        // First query populates cache
        #expect(lib.allArtists().count == 1)
        #expect(lib.allAlbums().count == 1)

        // Add more data
        let artist2 = UUID()
        lib.upsertArtists([syncArtist(id: artist2, name: "Artist 2")])
        lib.bumpRevision()

        // After bump, cache is cleared and new data is visible
        #expect(lib.allArtists().count == 2)
    }

    @Test func downloadedAlbumsReturnsOnlyWithDownloads() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let album1 = UUID(), album2 = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: artistId, name: "Downloaded Album"),
            syncAlbum(id: album2, artistId: artistId, name: "Not Downloaded"),
        ])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: album1, name: "T1"),
            syncTrack(id: t2, artistId: artistId, albumId: album2, name: "T2"),
        ])
        lib.markDownloaded(trackId: t1, relativePath: "p.m4a")

        let albums = lib.downloadedAlbums()
        #expect(albums.count == 1)
        #expect(albums[0].name == "Downloaded Album")
    }

    @Test func downloadedTracksReturnsSorted() throws {
        let lib = try makeTestLibrary()
        let a1 = UUID(), a2 = UUID()
        let album1 = UUID(), album2 = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([
            syncArtist(id: a1, name: "Zed", sortName: "Zed"),
            syncArtist(id: a2, name: "Alpha", sortName: "Alpha"),
        ])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: a1, name: "ZAlbum"),
            syncAlbum(id: album2, artistId: a2, name: "AAlbum"),
        ])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: a1, albumId: album1, name: "ZTrack"),
            syncTrack(id: t2, artistId: a2, albumId: album2, name: "ATrack"),
        ])
        lib.markDownloaded(trackId: t1, relativePath: "z.m4a")
        lib.markDownloaded(trackId: t2, relativePath: "a.m4a")

        let tracks = lib.downloadedTracks()
        #expect(tracks.count == 2)
        #expect(tracks[0].name == "ATrack")
        #expect(tracks[1].name == "ZTrack")
    }

    @Test func downloadedAlbumsForArtist() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let album1 = UUID(), album2 = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: artistId, name: "A1", releaseYear: 2020),
            syncAlbum(id: album2, artistId: artistId, name: "A2", releaseYear: 2010),
        ])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: album1, name: "T1"),
            syncTrack(id: t2, artistId: artistId, albumId: album2, name: "T2"),
        ])
        lib.markDownloaded(trackId: t1, relativePath: "p.m4a")

        let albums = lib.downloadedAlbumsForArtist(artistId)
        #expect(albums.count == 1)
        #expect(albums[0].name == "A1")
    }

    @Test func markAlbumUndownloaded() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: albumId, name: "S1", number: 1),
            syncTrack(id: t2, artistId: artistId, albumId: albumId, name: "S2", number: 2),
        ])
        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")
        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a")

        lib.markAlbumUndownloaded(albumId: albumId)

        #expect(!lib.isDownloaded(trackId: t1))
        #expect(!lib.isDownloaded(trackId: t2))
    }

    @Test func markArtistUndownloaded() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let album1 = UUID(), album2 = UUID()
        let t1 = UUID(), t2 = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "Artist")])
        lib.upsertAlbums([
            syncAlbum(id: album1, artistId: artistId, name: "A1"),
            syncAlbum(id: album2, artistId: artistId, name: "A2"),
        ])
        lib.upsertTracks([
            syncTrack(id: t1, artistId: artistId, albumId: album1, name: "T1"),
            syncTrack(id: t2, artistId: artistId, albumId: album2, name: "T2"),
        ])
        lib.markDownloaded(trackId: t1, relativePath: "p1.m4a")
        lib.markDownloaded(trackId: t2, relativePath: "p2.m4a")

        lib.markArtistUndownloaded(artistId: artistId)

        #expect(!lib.isDownloaded(trackId: t1))
        #expect(!lib.isDownloaded(trackId: t2))
    }

    @Test func availableTracksOnline() throws {
        let lib = try makeTestLibrary()
        let artist = Artist(id: UUID(), name: "A", sortName: "A", slug: "a")
        let tracks = [
            Track(id: UUID(), artistId: artist.id, albumArtistId: artist.id, albumId: UUID(),
                  artist: artist, albumArtistSortName: "A", name: "T1", disc: 1, number: 1,
                  duration: 100, mimetype: "audio/mp4", streamUrl: "/s", isDownloaded: false),
            Track(id: UUID(), artistId: artist.id, albumArtistId: artist.id, albumId: UUID(),
                  artist: artist, albumArtistSortName: "A", name: "T2", disc: 1, number: 2,
                  duration: 100, mimetype: "audio/mp4", streamUrl: "/s", isDownloaded: true),
        ]
        // Online: all tracks available
        #expect(lib.availableTracks(tracks, isOnline: true).count == 2)
        // Offline: only downloaded
        #expect(lib.availableTracks(tracks, isOnline: false).count == 1)
        #expect(lib.availableTracks(tracks, isOnline: false)[0].name == "T2")
    }

    @Test func availableItemsOnlineVsOffline() throws {
        let lib = try makeTestLibrary()
        let artist = Artist(id: UUID(), name: "A", sortName: "A", slug: "a")
        let t1 = Track(id: UUID(), artistId: artist.id, albumArtistId: artist.id, albumId: UUID(),
                       artist: artist, albumArtistSortName: "A", name: "T1", disc: 1, number: 1,
                       duration: 100, mimetype: "audio/mp4", streamUrl: "/s", isDownloaded: false)
        let t2 = Track(id: UUID(), artistId: artist.id, albumArtistId: artist.id, albumId: UUID(),
                       artist: artist, albumArtistSortName: "A", name: "T2", disc: 1, number: 2,
                       duration: 100, mimetype: "audio/mp4", streamUrl: "/s", isDownloaded: true)
        let items = [QueueItem(track: t1), QueueItem(track: t2)]

        #expect(lib.availableItems(items, isOnline: true).count == 2)
        #expect(lib.availableItems(items, isOnline: false).count == 1)
        #expect(lib.availableItems(items, isOnline: false)[0].track.name == "T2")
    }
}

// MARK: - Apply Deletions

@Suite(.serialized) struct MusicLibraryApplyDeletionTests {

    @Test func applyDeletionRemovesTrack() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let trackId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "A")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(id: trackId, artistId: artistId, albumId: albumId, name: "Track")])
        lib.bumpRevision()

        #expect(lib.allTracks().count == 1)

        lib.applyDeletions([SyncDeletion(entityType: "track", entityId: trackId)])
        lib.bumpRevision()

        #expect(lib.allTracks().isEmpty)
    }

    @Test func applyDeletionRemovesAlbumCascadesToTracks() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "A")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album", trackCount: 2)])
        lib.upsertTracks([
            syncTrack(artistId: artistId, albumId: albumId, name: "T1", number: 1),
            syncTrack(artistId: artistId, albumId: albumId, name: "T2", number: 2),
        ])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "album", entityId: albumId)])
        lib.bumpRevision()

        #expect(lib.allAlbums().isEmpty)
        #expect(lib.allTracks().isEmpty)
    }

    @Test func applyDeletionRemovesArtistCascadesAll() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        let albumId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "A")])
        lib.upsertAlbums([syncAlbum(id: albumId, artistId: artistId, name: "Album")])
        lib.upsertTracks([syncTrack(artistId: artistId, albumId: albumId, name: "Track")])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "artist", entityId: artistId)])
        lib.bumpRevision()

        #expect(lib.allArtists().isEmpty)
        #expect(lib.allAlbums().isEmpty)
        #expect(lib.allTracks().isEmpty)
    }

    @Test func applyDeletionEmptyListNoOp() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "A")])
        lib.bumpRevision()

        lib.applyDeletions([])
        lib.bumpRevision()

        #expect(lib.allArtists().count == 1)
    }

    @Test func applyDeletionUnknownIdNoOp() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "A")])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "artist", entityId: UUID())])
        lib.bumpRevision()

        #expect(lib.allArtists().count == 1)
    }

    @Test func applyDeletionUnknownEntityTypeIgnored() throws {
        let lib = try makeTestLibrary()
        let artistId = UUID()
        lib.upsertArtists([syncArtist(id: artistId, name: "A")])
        lib.bumpRevision()

        lib.applyDeletions([SyncDeletion(entityType: "playlist", entityId: artistId)])
        lib.bumpRevision()

        #expect(lib.allArtists().count == 1)
    }
}
