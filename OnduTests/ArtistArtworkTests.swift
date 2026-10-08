import Foundation
import SwiftData
import Testing
@testable import Ondu

@MainActor
struct ArtistArtworkLibraryTests {

    private func makeLibrary() throws -> MusicLibrary {
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return MusicLibrary(container: container)
    }

    private func artist(_ name: String, artwork: [ArtworkVariant] = []) -> SyncArtist {
        SyncArtist(id: UUID(), name: name, sortName: name, slug: name.lowercased(),
                   albumCount: 1, insertedAt: Date(), artwork: artwork)
    }

    private let variant = ArtworkVariant(url: URL(string: "https://example.com/a.jpg")!,
                                         width: 600, height: 400)

    @Test func keepsTheVariantsOnTheArtistItBuilds() throws {
        let library = try makeLibrary()
        library.upsertArtists([artist("Avery Linde", artwork: [variant])])
        library.bumpRevision()

        #expect(try #require(library.allArtists().first).artwork == [variant])
    }

    @Test func leavesArtworkEmptyWhenTheServerSendsNone() throws {
        let library = try makeLibrary()
        library.upsertArtists([artist("Juniper Weekes")])
        library.bumpRevision()

        #expect(try #require(library.allArtists().first).artwork.isEmpty)
    }

    /// An upload replaces what was there, and the URLs carry a version hash — so a later
    /// sync has to overwrite rather than merge.
    @Test func replacesArtworkOnASubsequentSync() throws {
        let library = try makeLibrary()
        let existing = artist("Avery Linde", artwork: [variant])
        library.upsertArtists([existing])
        library.bumpRevision()

        var updated = existing
        updated.artwork = []
        library.upsertArtists([updated])
        library.bumpRevision()

        #expect(try #require(library.allArtists().first).artwork.isEmpty)
    }

    /// Artists aren't square: the variant chosen has to be the one wide enough for the
    /// circle, not the one whose name sounds right.
    @Test func picksAVariantWideEnoughForTheCircle() {
        let variants = [
            ArtworkVariant(url: URL(string: "https://example.com/s.jpg")!, width: 100, height: 70),
            ArtworkVariant(url: URL(string: "https://example.com/m.jpg")!, width: 400, height: 280),
            ArtworkVariant(url: URL(string: "https://example.com/l.jpg")!, width: 1200, height: 840),
        ]
        #expect(variants.covering(pixelWidth: 132)?.width == 400)
    }
}
