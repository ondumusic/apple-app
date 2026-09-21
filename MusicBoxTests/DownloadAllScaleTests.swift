import Foundation
import SwiftData
import Testing
@testable import MusicBox

@Suite(.serialized)
struct DownloadAllScaleTests {

    @Test func downloadAllAtLibraryScale() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
                 LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
            configurations: config
        )
        let lib = MusicLibrary(container: container)
        let now = Date()

        var artists: [SyncArtist] = []
        var albums: [SyncAlbum] = []
        var tracks: [SyncTrack] = []
        for a in 0..<200 {
            let aid = UUID()
            artists.append(SyncArtist(id: aid, name: "Artist \(a)", sortName: "Artist \(a)",
                                      slug: "artist-\(a)", albumCount: 2, insertedAt: now))
            for b in 0..<2 {
                let bid = UUID()
                albums.append(SyncAlbum(id: bid, artistId: aid, name: "Album \(a)-\(b)",
                                        sortName: "Album \(a)-\(b)", slug: "album-\(a)-\(b)",
                                        releaseYear: 2000, artworkUrl: nil, isUnknown: false,
                                        trackCount: 11, insertedAt: now))
                for t in 0..<11 {
                    let tid = UUID()
                    tracks.append(SyncTrack(id: tid, artistId: aid, albumArtistId: aid, albumId: bid,
                                            name: "Track \(t)", disc: 1, number: t + 1,
                                            duration: 200, mimetype: "audio/mp4",
                                            streamUrl: "/stream/\(tid)", downloadUrl: "/download/\(tid)",
                                            insertedAt: now))
                }
            }
        }
        lib.upsertArtists(artists)
        lib.upsertAlbums(albums)
        lib.upsertTracks(tracks)
        lib.bumpRevision()

        let service = DownloadService(baseURL: URL(string: "https://example.com/api")!,
                                      sessionToken: "test-token", musicLibrary: lib,
                                      settings: makeTestSettings())
        // Isolate the enqueue path — we're measuring the scan, not URLSession.
        service.isPaused = true

        let start = Date()
        service.downloadAll(library: lib)
        let elapsed = Date().timeIntervalSince(start) * 1000

        #expect(service.pendingQueue.count == tracks.count)
        // Was quadratic plus a SwiftData fetch per track, which hung the app on the
        // click that started it; ~230ms at this size now. The bound is deliberately
        // loose — it's here to catch a return to that shape, not to police milliseconds.
        #expect(elapsed < 2000, "downloadAll took \(Int(elapsed))ms for \(tracks.count) tracks")
    }
}
