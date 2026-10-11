import Foundation
import Testing

@testable import Ondu

private func variant(_ width: Int) -> ArtworkVariant {
    ArtworkVariant(url: URL(string: "https://example.com/\(width).jpg")!, width: width, height: width)
}

@Suite
struct ArtworkVariantSelectionTests {

    private let sizes = [variant(64), variant(300), variant(640), variant(1200)]

    @Test func picksTheSmallestThatCoversTheRequest() {
        #expect(sizes.covering(pixelWidth: 100)?.width == 300)
        #expect(sizes.covering(pixelWidth: 300)?.width == 300)
        #expect(sizes.covering(pixelWidth: 301)?.width == 640)
    }

    /// Artwork is never upscaled by the server, so "bigger than every variant" is a real
    /// case rather than an error — the source image simply isn't that large.
    @Test func fallsBackToTheLargestWhenNothingIsBigEnough() {
        #expect(sizes.covering(pixelWidth: 4000)?.width == 1200)
    }

    @Test func hasNothingToPickFromWhenEmpty() {
        #expect([ArtworkVariant]().covering(pixelWidth: 300) == nil)
        #expect([ArtworkVariant]().largest == nil)
    }

    @Test func largestIsTheWidest() {
        #expect(sizes.largest?.width == 1200)
    }

    @Test func doesNotAssumeTheServerOrdersThem() {
        let shuffled = [variant(640), variant(64), variant(1200), variant(300)]
        #expect(shuffled.covering(pixelWidth: 100)?.width == 300)
        #expect(shuffled.largest?.width == 1200)
    }
}

@Suite
struct AlbumArtworkDecodingTests {

    private func decodeSyncAlbum(_ json: String) throws -> SyncAlbum {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncAlbum.self, from: Data(json.utf8))
    }

    private func body(artwork: String, artworkUrl: String) -> String {
        """
        {"id":"7c388624-2362-45e2-ae94-ee9aa7a65cb6",
         "artistId":"7c388624-2362-45e2-ae94-ee9aa7a65cb7",
         "name":"A","sortName":"A","slug":"a","isUnknown":false,"trackCount":1,
         "insertedAt":"2026-01-01T00:00:00Z",
         "artworkUrl":\(artworkUrl),"artwork":\(artwork)}
        """
    }

    @Test func readsTheVariants() throws {
        let album = try decodeSyncAlbum(
            body(
                artwork: """
                    [{"url":"https://example.com/s.jpg","width":300,"height":300},
                     {"url":"https://example.com/l.jpg","width":1200,"height":1200}]
                    """,
                artworkUrl: "\"https://example.com/l.jpg\""))

        #expect(album.artwork.count == 2)
        #expect(album.artwork.covering(pixelWidth: 200)?.width == 300)
    }

    /// `artworkUrl` is deprecated and documented as the largest variant, so it's derived
    /// rather than read — the day the server drops it, nothing changes here.
    @Test func derivesTheLegacyUrlFromTheVariants() throws {
        let album = try decodeSyncAlbum(
            body(
                artwork: """
                    [{"url":"https://example.com/s.jpg","width":300,"height":300},
                     {"url":"https://example.com/l.jpg","width":1200,"height":1200}]
                    """,
                artworkUrl: "null"))

        #expect(album.artworkUrl?.absoluteString == "https://example.com/l.jpg")
    }

    /// Until the new server ships, responses carry only the deprecated field.
    @Test func stillWorksWithNoVariantsAtAll() throws {
        let album = try decodeSyncAlbum(body(artwork: "[]", artworkUrl: "\"https://example.com/old.jpg\""))

        #expect(album.artwork.isEmpty)
        #expect(album.artworkUrl?.absoluteString == "https://example.com/old.jpg")
    }

    @Test func toleratesTheArtworkKeyBeingAbsent() throws {
        let json = """
            {"id":"7c388624-2362-45e2-ae94-ee9aa7a65cb6",
             "artistId":"7c388624-2362-45e2-ae94-ee9aa7a65cb7",
             "name":"A","sortName":"A","slug":"a","isUnknown":false,"trackCount":1,
             "insertedAt":"2026-01-01T00:00:00Z","artworkUrl":"https://example.com/old.jpg"}
            """
        #expect(try decodeSyncAlbum(json).artworkUrl?.absoluteString == "https://example.com/old.jpg")
    }
}
