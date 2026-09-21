import Foundation
import Testing
@testable import MusicBox

private func track(_ name: String, artist artistName: String, albumArtist: String? = nil,
                   album albumName: String = "Album", year: Int? = nil,
                   disc: Int = 1, number: Int = 1, duration: Double = 100) -> Track {
    let artist = Artist(id: UUID(), name: artistName, sortName: artistName, slug: "a")
    let albumArtistName = albumArtist ?? artistName
    return Track(id: UUID(), artistId: artist.id, albumArtistId: artist.id, albumId: UUID(),
                 artist: artist, albumArtistName: albumArtistName,
                 albumArtistSortName: albumArtistName,
                 album: Track.TrackAlbum(id: UUID(), name: albumName, artworkUrl: nil,
                                         releaseYear: year),
                 name: name, disc: disc, number: number, duration: duration,
                 mimetype: "audio/mp4", streamUrl: "/s")
}

struct TrackSortTests {

    /// The Artist column shows the album artist, so that's what a click on it sorts by.
    @Test func sortsByTheAlbumArtistTheColumnShows() {
        let tracks = [track("T1", artist: "Lin-Manuel Miranda", albumArtist: "Original Cast"),
                      track("T2", artist: "Zoo", albumArtist: "A Camp")]
        let sorted = TrackSort(column: .artist, ascending: true).sorted(tracks)
        #expect(sorted.map(\.albumArtistName) == ["A Camp", "Original Cast"])
    }

    /// By sort name, as the library's own default order does — so "The Beatles" lands
    /// under B rather than T.
    @Test func artistSortUsesTheSortName() {
        var beatles = track("T1", artist: "The Beatles", albumArtist: "The Beatles")
        beatles.albumArtistSortName = "Beatles, The"
        let cure = track("T2", artist: "Cure", albumArtist: "Cure")
        let sorted = TrackSort(column: .artist, ascending: true).sorted([cure, beatles])
        #expect(sorted.map(\.albumArtistName) == ["The Beatles", "Cure"])
    }

    @Test func descendingPutsTheLastArtistFirst() {
        let tracks = [track("T1", artist: "A Camp"), track("T2", artist: "Zoo")]
        let sorted = TrackSort(column: .artist, ascending: false).sorted(tracks)
        #expect(sorted.map(\.albumArtistName) == ["Zoo", "A Camp"])
    }

    @Test func titleSortIsLocalised() {
        let tracks = [track("Ziggy", artist: "A"), track("apple", artist: "A"), track("Émile", artist: "A")]
        let sorted = TrackSort(column: .title, ascending: true).sorted(tracks)
        #expect(sorted.map(\.name) == ["apple", "Émile", "Ziggy"])
    }

    @Test func durationSortsNumerically() {
        let tracks = [track("A", artist: "X", duration: 300), track("B", artist: "X", duration: 90)]
        let sorted = TrackSort(column: .duration, ascending: true).sorted(tracks)
        #expect(sorted.map(\.duration) == [90, 300])
    }

    /// The point of the whole exercise: sorting by a column groups by it, it doesn't
    /// throw the library's ordering away. Artist ascending still walks each artist's
    /// albums in order, and each album's tracks in disc/number order.
    @Test func sortingByArtistKeepsTheAlbumOrderUnderneath() {
        let tracks = [
            track("Late", artist: "A", album: "Second", disc: 1, number: 2),
            track("Early", artist: "A", album: "First", disc: 1, number: 2),
            track("First track", artist: "A", album: "First", disc: 1, number: 1),
            track("Disc two", artist: "A", album: "First", disc: 2, number: 1)
        ]
        let sorted = TrackSort(column: .artist, ascending: true).sorted(tracks)
        #expect(sorted.map(\.name) == ["First track", "Early", "Disc two", "Late"])
    }

    /// Descending flips the column you clicked and nothing else — an artist's albums
    /// stay in album order rather than running backwards.
    @Test func descendingReversesOnlyTheColumnClicked() {
        let tracks = [
            track("A1", artist: "Zoo", album: "Alpha", number: 1),
            track("A2", artist: "Zoo", album: "Alpha", number: 2),
            track("B1", artist: "Aviary", album: "Beta", number: 1)
        ]
        let sorted = TrackSort(column: .artist, ascending: false).sorted(tracks)
        #expect(sorted.map(\.name) == ["A1", "A2", "B1"])
    }

    @Test func sortsByYearWhenTheColumnIsShown() {
        let tracks = [track("New", artist: "A", year: 2020), track("Old", artist: "A", year: 1999)]
        let sorted = TrackSort(column: .year, ascending: true).sorted(tracks)
        #expect(sorted.map(\.name) == ["Old", "New"])
    }

    @Test func roundTripsThroughAppStorage() {
        let sort = TrackSort(column: .album, ascending: false)
        #expect(TrackSort(rawValue: sort.rawValue) == sort)
        #expect(TrackSort(rawValue: "") == nil)
    }
}
