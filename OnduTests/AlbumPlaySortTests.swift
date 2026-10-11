import Foundation
import SwiftData
import Testing

@testable import Ondu

private func album(_ name: String, id: UUID = UUID()) -> Album {
    Album(
        id: id, artistId: UUID(), name: name, sortName: name, slug: name.lowercased(),
        releaseYear: nil, isUnknown: false, artworkUrl: nil, artwork: [], insertedAt: Date())
}

private func stats(_ pairs: [(UUID, Int, Date?)]) -> [UUID: MusicLibrary.AlbumPlayStats] {
    Dictionary(
        uniqueKeysWithValues: pairs.map {
            ($0.0, MusicLibrary.AlbumPlayStats(playCount: $0.1, lastPlayedAt: $0.2))
        })
}

struct AlbumPlaySortTests {

    @Test func sortsByTotalPlays() {
        let a = album("A")
        let b = album("B")
        let c = album("C")
        let sorted = AlbumSortOption.plays.sorted(
            [a, b, c], ascending: false,
            playStats: stats([(a.id, 3, nil), (b.id, 40, nil)]))
        #expect(sorted.map(\.name) == ["B", "A", "C"])
    }

    @Test func sortsByMostRecentlyPlayed() {
        let now = Date()
        let a = album("A")
        let b = album("B")
        let c = album("C")
        let sorted = AlbumSortOption.lastPlayed.sorted(
            [a, b, c], ascending: false,
            playStats: stats([(a.id, 1, now.addingTimeInterval(-3600)), (b.id, 1, now)]))
        #expect(sorted.map(\.name) == ["B", "A", "C"])
    }

    /// Both start from the top: nobody opens "Plays" wanting what they've played least.
    @Test func bothPlaySortsStartDescending() {
        #expect(AlbumSortOption.plays.defaultAscending == false)
        #expect(AlbumSortOption.lastPlayed.defaultAscending == false)
    }

    @Test func onlyThePlaySortsAskForTheAggregate() {
        #expect(AlbumSortOption.plays.needsPlayStats)
        #expect(AlbumSortOption.lastPlayed.needsPlayStats)
        #expect(!AlbumSortOption.artist.needsPlayStats)
        #expect(!AlbumSortOption.dateAdded.needsPlayStats)
    }
}

struct AlbumPlayStatsTests {

    private func makeLibrary() throws -> MusicLibrary {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
            LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return MusicLibrary(container: container)
    }

    /// An album's figures are its tracks' — the sum of their plays, and the latest of
    /// their dates.
    @Test func addsUpTheAlbumsTracks() throws {
        let lib = try makeLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let now = Date()
        let older = now.addingTimeInterval(-7200)
        lib.upsertArtists([
            SyncArtist(
                id: artistId, name: "A", sortName: "A", slug: "a",
                albumCount: 1, insertedAt: now)
        ])
        lib.upsertAlbums([
            SyncAlbum(
                id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                slug: "album", releaseYear: nil, artworkUrl: nil,
                isUnknown: false, trackCount: 3, insertedAt: now)
        ])
        lib.upsertTracks([
            SyncTrack(
                id: UUID(), artistId: artistId, albumArtistId: artistId, albumId: albumId,
                name: "1", disc: 1, number: 1, duration: 100, mimetype: "audio/mp4",
                streamUrl: "/s/1", downloadUrl: "/d/1", insertedAt: now, lufs: nil,
                playCount: 2, lastPlayedAt: older),
            SyncTrack(
                id: UUID(), artistId: artistId, albumArtistId: artistId, albumId: albumId,
                name: "2", disc: 1, number: 2, duration: 100, mimetype: "audio/mp4",
                streamUrl: "/s/2", downloadUrl: "/d/2", insertedAt: now, lufs: nil,
                playCount: 5, lastPlayedAt: now),
            SyncTrack(
                id: UUID(), artistId: artistId, albumArtistId: artistId, albumId: albumId,
                name: "3", disc: 1, number: 3, duration: 100, mimetype: "audio/mp4",
                streamUrl: "/s/3", downloadUrl: "/d/3", insertedAt: now, lufs: nil),
        ])
        lib.bumpRevision()

        let stats = try #require(lib.albumPlayStats()[albumId])
        #expect(stats.playCount == 7)
        #expect(stats.lastPlayedAt == now)
    }

    @Test func leavesOutAnAlbumNobodyHasPlayed() throws {
        let lib = try makeLibrary()
        let artistId = UUID()
        let albumId = UUID()
        let now = Date()
        lib.upsertArtists([
            SyncArtist(
                id: artistId, name: "A", sortName: "A", slug: "a",
                albumCount: 1, insertedAt: now)
        ])
        lib.upsertAlbums([
            SyncAlbum(
                id: albumId, artistId: artistId, name: "Album", sortName: "Album",
                slug: "album", releaseYear: nil, artworkUrl: nil,
                isUnknown: false, trackCount: 1, insertedAt: now)
        ])
        lib.upsertTracks([
            SyncTrack(
                id: UUID(), artistId: artistId, albumArtistId: artistId,
                albumId: albumId, name: "1", disc: 1, number: 1, duration: 100,
                mimetype: "audio/mp4", streamUrl: "/s/1", downloadUrl: "/d/1",
                insertedAt: now)
        ])
        lib.bumpRevision()

        #expect(lib.albumPlayStats()[albumId] == nil)
    }
}
