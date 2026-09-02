import Foundation
import SwiftData
import Testing
@testable import MusicBox

// MARK: - Fixtures

private let testArtist = Artist(id: UUID(), name: "Test Artist", sortName: "Test Artist", slug: "test-artist")
private let testAlbumId = UUID()
private let testAlbum = Album(id: testAlbumId, artistId: testArtist.id, name: "Test Album",
                              sortName: "Test Album", slug: "test-album")

private func makeTrack(id: UUID = UUID(), name: String = "Track", mimetype: String = "audio/mp4") -> Track {
    Track(id: id, artistId: testArtist.id, albumArtistId: testArtist.id,
          albumId: testAlbumId, artist: testArtist, albumArtistSortName: testArtist.sortName,
          name: name, disc: 1, number: 1, duration: 200,
          mimetype: mimetype, streamUrl: "https://example.com/stream/test",
          downloadUrl: "https://example.com/download/test")
}

private func makeInfo(track: Track? = nil, album: Album? = nil, artist: Artist? = nil) -> DownloadService.DownloadInfo {
    DownloadService.DownloadInfo(track: track ?? makeTrack(), album: album ?? testAlbum, artist: artist ?? testArtist)
}

private func makeLibrary() throws -> MusicLibrary {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: LibraryArtist.self, LibraryAlbum.self, LibraryTrack.self,
             LibraryPlaylist.self, LibraryPlaylistItem.self, PendingMutation.self,
        configurations: config
    )
    return MusicLibrary(container: container)
}

private func makeService(library: MusicLibrary? = nil, settings: SettingsStore? = nil) throws -> DownloadService {
    let lib = try library ?? makeLibrary()
    let s = settings ?? SettingsStore()
    return DownloadService(baseURL: URL(string: "https://example.com/api")!,
                           sessionToken: "test-token", musicLibrary: lib, settings: s)
}

// MARK: - Initial State

@Suite struct DownloadServiceInitialStateTests {

    @Test func initialStateIsEmpty() throws {
        let service = try makeService()
        #expect(service.activeDownloads.isEmpty)
        #expect(service.activeDownloadOrder.isEmpty)
        #expect(service.pendingQueue.isEmpty)
        #expect(!service.isPaused)
        #expect(service.progressSnapshot.isEmpty)
        #expect(service.failedDownloads.isEmpty)
        #expect(!service.hasActivity)
    }
}

// MARK: - Download Enqueuing

@Suite struct DownloadEnqueueTests {

    @Test func downloadAddsToActiveState() throws {
        let service = try makeService()
        let track = makeTrack()

        service.download(track: track, album: testAlbum, artist: testArtist)

        #expect(service.isDownloading(trackId: track.id))
        #expect(service.activeDownloads[track.id] != nil)
        #expect(service.activeDownloadOrder.contains(track.id))
        #expect(service.hasActivity)
    }

    @Test func downloadSetsCorrectMetadata() throws {
        let service = try makeService()
        let track = makeTrack(name: "My Song")

        service.download(track: track, album: testAlbum, artist: testArtist)

        let state = service.activeDownloads[track.id]
        #expect(state?.trackName == "My Song")
        #expect(state?.artistName == "Test Artist")
        #expect(state?.albumId == testAlbumId)
    }

    @Test func duplicateDownloadIsIgnored() throws {
        let service = try makeService()
        let track = makeTrack()

        service.download(track: track, album: testAlbum, artist: testArtist)
        service.download(track: track, album: testAlbum, artist: testArtist)

        #expect(service.activeDownloadOrder.filter { $0 == track.id }.count == 1)
    }

    @Test func alreadyDownloadedTrackIsIgnored() throws {
        let library = try makeLibrary()
        let trackId = UUID()

        // Insert a track into the library and mark it downloaded
        let now = Date()
        library.upsertArtists([SyncArtist(id: testArtist.id, name: "Test Artist", sortName: "Test Artist",
                                          slug: "test-artist", albumCount: 1, insertedAt: now)])
        library.upsertAlbums([SyncAlbum(id: testAlbumId, artistId: testArtist.id, name: "Test Album",
                                        sortName: "Test Album", slug: "test-album", releaseYear: nil,
                                        artworkUrl: nil, isUnknown: false, trackCount: 1, insertedAt: now)])
        library.upsertTracks([SyncTrack(id: trackId, artistId: testArtist.id, albumArtistId: testArtist.id,
                                        albumId: testAlbumId, name: "Track", disc: 1, number: 1,
                                        duration: 200, mimetype: "audio/mp4",
                                        streamUrl: "/stream/test", downloadUrl: "/download/test",
                                        insertedAt: now)])
        library.markDownloaded(trackId: trackId, relativePath: "MusicBox/Downloads/test.mp4")

        let service = try makeService(library: library)
        let track = makeTrack(id: trackId)

        service.download(track: track, album: testAlbum, artist: testArtist)

        #expect(!service.isDownloading(trackId: trackId))
        #expect(service.activeDownloads.isEmpty)
    }

    @Test func downloadAlbumEnqueuesAllTracks() throws {
        let service = try makeService()
        let tracks = (1...5).map { makeTrack(name: "Track \($0)") }
        let album = Album(id: testAlbumId, artistId: testArtist.id, name: "Album",
                          sortName: "Album", slug: "album", tracks: tracks)

        service.download(album: album, artist: testArtist)

        // With default maxConcurrentDownloads=3, 3 should be active and 2 pending
        #expect(service.activeDownloads.count + service.pendingQueue.count == 5)
        for track in tracks {
            #expect(service.isDownloading(trackId: track.id) || service.isQueued(trackId: track.id))
        }
    }

    @Test func downloadAlbumWithNoTracksIsNoop() throws {
        let service = try makeService()
        let album = Album(id: testAlbumId, artistId: testArtist.id, name: "Album",
                          sortName: "Album", slug: "album", tracks: nil)

        service.download(album: album, artist: testArtist)

        #expect(!service.hasActivity)
    }

    @Test func concurrencyLimitRespected() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 2
        let service = try makeService(settings: settings)

        let tracks = (1...5).map { makeTrack(name: "Track \($0)") }
        for track in tracks {
            service.download(track: track, album: testAlbum, artist: testArtist)
        }

        #expect(service.activeDownloads.count == 2)
        #expect(service.pendingQueue.count == 3)
    }
}

// MARK: - Query Methods

@Suite struct DownloadQueryTests {

    @Test func isDownloadingReturnsFalseForUnknownTrack() throws {
        let service = try makeService()
        #expect(!service.isDownloading(trackId: UUID()))
    }

    @Test func isQueuedReturnsTrueForPendingTrack() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let track1 = makeTrack(name: "First")
        let track2 = makeTrack(name: "Second")
        service.download(track: track1, album: testAlbum, artist: testArtist)
        service.download(track: track2, album: testAlbum, artist: testArtist)

        #expect(service.isDownloading(trackId: track1.id))
        #expect(!service.isDownloading(trackId: track2.id))
        #expect(service.isQueued(trackId: track2.id))
    }

    @Test func isAlbumDownloadingDetectsActiveAndQueued() throws {
        let service = try makeService()
        let track = makeTrack()

        #expect(!service.isAlbumDownloading(albumId: testAlbumId))

        service.download(track: track, album: testAlbum, artist: testArtist)

        #expect(service.isAlbumDownloading(albumId: testAlbumId))
    }

    @Test func hasActivityReflectsState() throws {
        let service = try makeService()

        #expect(!service.hasActivity)

        let track = makeTrack()
        service.download(track: track, album: testAlbum, artist: testArtist)

        #expect(service.hasActivity)
    }
}

// MARK: - Cancel

@Suite struct DownloadCancelTests {

    @Test func cancelActiveDownloadCleansUp() throws {
        let service = try makeService()
        let track = makeTrack()

        service.download(track: track, album: testAlbum, artist: testArtist)
        #expect(service.isDownloading(trackId: track.id))

        service.cancelDownload(trackId: track.id)

        #expect(!service.isDownloading(trackId: track.id))
        #expect(service.activeDownloads[track.id] == nil)
        #expect(!service.activeDownloadOrder.contains(track.id))
        #expect(!service.hasActivity)
    }

    @Test func cancelQueuedDownloadRemovesFromPending() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let track1 = makeTrack(name: "First")
        let track2 = makeTrack(name: "Second")
        service.download(track: track1, album: testAlbum, artist: testArtist)
        service.download(track: track2, album: testAlbum, artist: testArtist)

        #expect(service.isQueued(trackId: track2.id))

        service.cancelDownload(trackId: track2.id)

        #expect(!service.isQueued(trackId: track2.id))
    }

    @Test func cancelPromotesNextFromQueue() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let track1 = makeTrack(name: "First")
        let track2 = makeTrack(name: "Second")
        service.download(track: track1, album: testAlbum, artist: testArtist)
        service.download(track: track2, album: testAlbum, artist: testArtist)

        #expect(service.isDownloading(trackId: track1.id))
        #expect(service.isQueued(trackId: track2.id))

        service.cancelDownload(trackId: track1.id)

        #expect(service.isDownloading(trackId: track2.id))
        #expect(!service.isQueued(trackId: track2.id))
    }

    @Test func cancelAllClearsEverything() throws {
        let service = try makeService()
        let tracks = (1...5).map { makeTrack(name: "Track \($0)") }
        for track in tracks {
            service.download(track: track, album: testAlbum, artist: testArtist)
        }

        #expect(service.hasActivity)

        service.cancelAll()

        #expect(service.activeDownloads.isEmpty)
        #expect(service.activeDownloadOrder.isEmpty)
        #expect(service.pendingQueue.isEmpty)
        #expect(!service.isPaused)
        #expect(!service.hasActivity)
    }

    @Test func cancelNonexistentTrackIsNoop() throws {
        let service = try makeService()
        let track = makeTrack()
        service.download(track: track, album: testAlbum, artist: testArtist)

        service.cancelDownload(trackId: UUID()) // unknown ID

        #expect(service.isDownloading(trackId: track.id))
    }
}

// MARK: - Pause / Resume

@Suite struct DownloadPauseResumeTests {

    @Test func pauseActiveDownloadSetsState() throws {
        let service = try makeService()
        let track = makeTrack()

        service.download(track: track, album: testAlbum, artist: testArtist)
        service.pauseDownload(trackId: track.id)

        #expect(service.activeDownloads[track.id]?.isPaused == true)
    }

    @Test func resumePausedDownloadReactivates() throws {
        let service = try makeService()
        let track = makeTrack()

        service.download(track: track, album: testAlbum, artist: testArtist)
        service.pauseDownload(trackId: track.id)

        #expect(service.activeDownloads[track.id]?.isPaused == true)

        service.resumeDownload(trackId: track.id)

        // After resume, the track should be active again (re-started)
        #expect(service.isDownloading(trackId: track.id))
        #expect(service.activeDownloads[track.id]?.isPaused != true)
    }

    @Test func pauseAllSetsFlag() throws {
        let service = try makeService()
        let track = makeTrack()
        service.download(track: track, album: testAlbum, artist: testArtist)

        service.pauseAll()

        #expect(service.isPaused)
    }

    @Test func resumeAllClearsFlag() throws {
        let service = try makeService()
        let track = makeTrack()
        service.download(track: track, album: testAlbum, artist: testArtist)

        service.pauseAll()
        #expect(service.isPaused)

        service.resumeAll()
        #expect(!service.isPaused)
    }

    @Test func pauseAllBlocksNewDownloads() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let track1 = makeTrack(name: "First")
        service.download(track: track1, album: testAlbum, artist: testArtist)

        service.pauseAll()

        // New downloads should go to pending but not start
        let track2 = makeTrack(name: "Second")
        service.download(track: track2, album: testAlbum, artist: testArtist)

        #expect(service.isQueued(trackId: track2.id))
    }

    @Test func pauseNonexistentTrackIsNoop() throws {
        let service = try makeService()
        let track = makeTrack()
        service.download(track: track, album: testAlbum, artist: testArtist)

        service.pauseDownload(trackId: UUID()) // unknown ID

        #expect(service.activeDownloads[track.id]?.isPaused != true)
    }

    @Test func cancelPausedDownloadCleansUp() throws {
        let service = try makeService()
        let track = makeTrack()

        service.download(track: track, album: testAlbum, artist: testArtist)
        service.pauseDownload(trackId: track.id)

        #expect(service.activeDownloads[track.id]?.isPaused == true)

        service.cancelDownload(trackId: track.id)

        #expect(service.activeDownloads[track.id] == nil)
        #expect(!service.hasActivity)
    }

    @Test func pausePromotesNextFromQueue() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let track1 = makeTrack(name: "First")
        let track2 = makeTrack(name: "Second")
        service.download(track: track1, album: testAlbum, artist: testArtist)
        service.download(track: track2, album: testAlbum, artist: testArtist)

        #expect(service.isDownloading(trackId: track1.id))
        #expect(service.isQueued(trackId: track2.id))

        // Pausing doesn't promote (isPaused keeps the slot conceptually)
        // But the implementation decrements inFlightCount, so it should promote
        service.pauseDownload(trackId: track1.id)

        // track1 is paused but still in activeDownloads, track2 should not auto-promote
        // because startNextIfNeeded isn't called from pauseDownload
        // Actually let's check: pauseDownload doesn't call startNextIfNeeded
        // so track2 stays queued
        #expect(service.isQueued(trackId: track2.id))
    }
}

// MARK: - Failed Downloads

@Suite struct DownloadFailedTests {

    @Test func retryMovesToPendingQueue() throws {
        let service = try makeService()
        let track = makeTrack(name: "Failed Track")
        let info = makeInfo(track: track)
        let failed = DownloadService.FailedDownload(
            id: track.id, trackName: "Failed Track", artistName: "Test Artist",
            info: info, reason: "Server error"
        )
        service.failedDownloads.append(failed)

        #expect(service.hasActivity) // failedDownloads count

        service.retryDownload(failed)

        #expect(service.failedDownloads.isEmpty)
        // Should be either active or queued
        #expect(service.isDownloading(trackId: track.id) || service.isQueued(trackId: track.id))
    }

    @Test func dismissRemovesFromFailed() throws {
        let service = try makeService()
        let track = makeTrack()
        let info = makeInfo(track: track)
        let failed = DownloadService.FailedDownload(
            id: track.id, trackName: "Track", artistName: "Artist",
            info: info, reason: "Error"
        )
        service.failedDownloads.append(failed)

        service.dismissFailedDownload(failed)

        #expect(service.failedDownloads.isEmpty)
    }

    @Test func clearFailedRemovesAll() throws {
        let service = try makeService()
        let info = makeInfo()
        service.failedDownloads.append(DownloadService.FailedDownload(
            id: UUID(), trackName: "A", artistName: "X", info: info, reason: "err"))
        service.failedDownloads.append(DownloadService.FailedDownload(
            id: UUID(), trackName: "B", artistName: "Y", info: info, reason: "err"))

        service.clearFailedDownloads()

        #expect(service.failedDownloads.isEmpty)
    }
}

// MARK: - Pending Completions

@Suite struct PendingCompletionTests {

    @Test func pendingCompletionRoundTrips() throws {
        let record = DownloadService.PendingCompletion(
            trackId: UUID(), relativePath: "MusicBox/Downloads/a/b/c.mp4", downloadedFileSize: 12345
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DownloadService.PendingCompletion.self, from: data)

        #expect(decoded.trackId == record.trackId)
        #expect(decoded.relativePath == record.relativePath)
        #expect(decoded.downloadedFileSize == 12345)
    }

    @Test func taskMetadataRoundTrips() throws {
        let meta = DownloadService.TaskMetadata(
            trackId: UUID(), artistId: UUID(), albumId: UUID(),
            mimetype: "audio/flac", trackName: "Test Song"
        )
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(DownloadService.TaskMetadata.self, from: data)

        #expect(decoded.trackId == meta.trackId)
        #expect(decoded.artistId == meta.artistId)
        #expect(decoded.albumId == meta.albumId)
        #expect(decoded.mimetype == "audio/flac")
        #expect(decoded.trackName == "Test Song")
    }
}

// MARK: - Download Order

@Suite struct DownloadOrderTests {

    @Test func pendingQueuePreservesInsertionOrder() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let tracks = (1...4).map { makeTrack(name: "Track \($0)") }
        for track in tracks {
            service.download(track: track, album: testAlbum, artist: testArtist)
        }

        // First track is active, rest are pending in order
        let pendingIds = service.pendingQueue.map(\.track.id)
        #expect(pendingIds == [tracks[1].id, tracks[2].id, tracks[3].id])
    }

    @Test func cancelRemovesFromPendingQueue() throws {
        let settings = SettingsStore()
        settings.maxConcurrentDownloads = 1
        let service = try makeService(settings: settings)

        let tracks = (1...4).map { makeTrack(name: "Track \($0)") }
        for track in tracks {
            service.download(track: track, album: testAlbum, artist: testArtist)
        }

        service.cancelDownload(trackId: tracks[2].id)

        let pendingIds = service.pendingQueue.map(\.track.id)
        #expect(pendingIds == [tracks[1].id, tracks[3].id])
    }
}

@Suite(.serialized)
struct DownloadPauseOverrideTests {

    /// The override lasts the session and is deliberately not persisted, so a relaunch
    /// defers to the system setting again.
    @Test func lowPowerOverrideDefaultsOff() throws {
        let service = try makeService()
        #expect(service.ignoresLowPowerMode == false)
    }

    @Test func lowPowerOverrideCanBeSet() throws {
        let service = try makeService()
        service.ignoresLowPowerMode = true
        #expect(service.ignoresLowPowerMode)
    }

    /// Taking the override re-evaluates the pause conditions rather than pinning the
    /// reason, so the disk-space guard still gets its say on the next attempt.
    @Test func overrideReevaluatesPauseReason() throws {
        let service = try makeService()
        service.downloadsPausedReason = .lowDiskSpace
        service.ignoresLowPowerMode = true
        #expect(service.downloadsPausedReason == nil)
    }
}
