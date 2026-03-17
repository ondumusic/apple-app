import Foundation
import Testing
@testable import MusicBox

struct TrackTests {

    @Test func formattedDurationMinutesAndSeconds() {
        let track = makeTrack(duration: 185) // 3:05
        #expect(track.formattedDuration == "3:05")
    }

    @Test func formattedDurationUnderOneMinute() {
        let track = makeTrack(duration: 45)
        #expect(track.formattedDuration == "0:45")
    }

    @Test func formattedDurationExactMinute() {
        let track = makeTrack(duration: 120)
        #expect(track.formattedDuration == "2:00")
    }

    @Test func formattedDurationZero() {
        let track = makeTrack(duration: 0)
        #expect(track.formattedDuration == "0:00")
    }

    @Test func formattedDurationLong() {
        let track = makeTrack(duration: 3661) // 61:01
        #expect(track.formattedDuration == "61:01")
    }

    @Test func formattedDurationFractionalSeconds() {
        let track = makeTrack(duration: 65.9)
        #expect(track.formattedDuration == "1:05")
    }
}

struct ArtistTests {

    @Test func sortNameDefaultsToName() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "The Beatles", "slug": "the-beatles"}
        """
        let artist = try JSONDecoder().decode(Artist.self, from: Data(json.utf8))
        #expect(artist.sortName == "The Beatles")
    }

    @Test func sortNameFromJSON() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "name": "The Beatles", "sort_name": "Beatles, The", "slug": "the-beatles"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let artist = try decoder.decode(Artist.self, from: Data(json.utf8))
        #expect(artist.sortName == "Beatles, The")
    }
}

struct AlbumTests {

    @Test func sortNameDefaultsToName() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000001", "artist_id": "00000000-0000-0000-0000-000000000002", "name": "Abbey Road", "slug": "abbey-road", "is_unknown": false}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let album = try decoder.decode(Album.self, from: Data(json.utf8))
        #expect(album.sortName == "Abbey Road")
    }
}

// MARK: - Helpers

private let testArtist = Artist(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    name: "Test Artist",
    sortName: "Test Artist",
    slug: "test-artist"
)

private func makeTrack(duration: Double) -> Track {
    Track(
        id: UUID(),
        artistId: testArtist.id,
        albumArtistId: testArtist.id,
        albumId: UUID(),
        artist: testArtist,
        albumArtistSortName: testArtist.sortName,
        name: "Test Track",
        disc: 1,
        number: 1,
        duration: duration,
        mimetype: "audio/mp4",
        streamUrl: "/stream/test"
    )
}
