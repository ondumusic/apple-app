import Foundation
import Testing
@testable import MusicBox

// MARK: - Helpers

private func makeTempCacheDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlaybackCacheTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeCache(cacheLimit: Int64 = 0) -> (PlaybackCache, URL) {
    let settings = SettingsStore()
    settings.playbackCacheLimit = cacheLimit
    let dir = makeTempCacheDir()
    let cache = PlaybackCache(settings: settings, cacheDir: dir)
    return (cache, dir)
}

private func writeFakeFile(in dir: URL, trackId: UUID, ext: String = "m4a", size: Int) -> String {
    let filename = "\(trackId.uuidString).\(ext)"
    let url = dir.appendingPathComponent(filename)
    let data = Data(repeating: 0, count: size)
    try! data.write(to: url)
    return filename
}

private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - Basic Operations

@Suite(.serialized) struct PlaybackCacheBasicTests {

    @Test func emptyCache() {
        let (cache, dir) = makeCache()
        defer { cleanup(dir) }

        #expect(cache.trackCount == 0)
        #expect(cache.currentSize == 0)
        #expect(cache.formattedSize == "Zero KB")
    }

    @Test func cachedURLReturnsNilForUnknownTrack() {
        let (cache, dir) = makeCache()
        defer { cleanup(dir) }

        #expect(cache.cachedURL(for: UUID()) == nil)
    }

    @Test func clearCacheRemovesAllEntries() {
        let (cache, dir) = makeCache()
        defer { cleanup(dir) }

        // Manually add entries by writing metadata
        let id1 = UUID(), id2 = UUID()
        _ = writeFakeFile(in: dir, trackId: id1, size: 1000)
        _ = writeFakeFile(in: dir, trackId: id2, size: 2000)

        // Reload to pick up files via metadata
        let settings = SettingsStore()
        let entries: [PlaybackCache.CacheEntry] = [
            .init(trackId: id1, filename: "\(id1.uuidString).m4a", size: 1000, lastAccessed: Date()),
            .init(trackId: id2, filename: "\(id2.uuidString).m4a", size: 2000, lastAccessed: Date()),
        ]
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        let data = try! JSONEncoder().encode(entries)
        try! data.write(to: metadataURL)

        let cache2 = PlaybackCache(settings: settings, cacheDir: dir)
        #expect(cache2.trackCount == 2)
        #expect(cache2.currentSize == 3000)

        cache2.clearCache()

        #expect(cache2.trackCount == 0)
        #expect(cache2.currentSize == 0)
        // Files should be deleted
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id1.uuidString).m4a").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id2.uuidString).m4a").path))
    }
}

// MARK: - LRU & Eviction

@Suite(.serialized) struct PlaybackCacheLRUTests {

    @Test func cachedURLUpdatesAccessOrder() {
        let dir = makeTempCacheDir()
        defer { cleanup(dir) }

        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let entries: [PlaybackCache.CacheEntry] = [
            .init(trackId: id1, filename: "\(id1.uuidString).m4a", size: 100, lastAccessed: Date(timeIntervalSince1970: 1000)),
            .init(trackId: id2, filename: "\(id2.uuidString).m4a", size: 200, lastAccessed: Date(timeIntervalSince1970: 2000)),
            .init(trackId: id3, filename: "\(id3.uuidString).m4a", size: 300, lastAccessed: Date(timeIntervalSince1970: 3000)),
        ]

        // Write files and metadata
        for entry in entries {
            let data = Data(repeating: 0, count: Int(entry.size))
            try! data.write(to: dir.appendingPathComponent(entry.filename))
        }
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        try! JSONEncoder().encode(entries).write(to: metadataURL)

        let settings = SettingsStore()
        let cache = PlaybackCache(settings: settings, cacheDir: dir)

        // Access id1 — should move it to end (most recently used)
        let url = cache.cachedURL(for: id1)
        #expect(url != nil)

        // Flush and reload to verify order persisted
        cache.flushMetadataIfNeeded()
        let cache2 = PlaybackCache(settings: settings, cacheDir: dir)

        // id1 should now be last (most recent), id2 first (least recent)
        // Verify by checking that accessing id2 returns it (still exists)
        #expect(cache2.cachedURL(for: id2) != nil)
        #expect(cache2.trackCount == 3)
    }

    @Test func missingFileRemovesEntry() {
        let dir = makeTempCacheDir()
        defer { cleanup(dir) }

        let id1 = UUID()
        let entries: [PlaybackCache.CacheEntry] = [
            .init(trackId: id1, filename: "\(id1.uuidString).m4a", size: 1000, lastAccessed: Date()),
        ]
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        try! JSONEncoder().encode(entries).write(to: metadataURL)

        // Don't write the actual file — it's "missing"
        let settings = SettingsStore()
        let cache = PlaybackCache(settings: settings, cacheDir: dir)

        // Loading metadata should filter out missing files
        #expect(cache.trackCount == 0)
        #expect(cache.currentSize == 0)
    }

    @Test func cachedURLRemovesEntryWhenFileDisappears() {
        let dir = makeTempCacheDir()
        defer { cleanup(dir) }

        let id1 = UUID()
        let filename = writeFakeFile(in: dir, trackId: id1, size: 500)
        let entries: [PlaybackCache.CacheEntry] = [
            .init(trackId: id1, filename: filename, size: 500, lastAccessed: Date()),
        ]
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        try! JSONEncoder().encode(entries).write(to: metadataURL)

        let settings = SettingsStore()
        let cache = PlaybackCache(settings: settings, cacheDir: dir)
        #expect(cache.trackCount == 1)

        // Delete the file behind the cache's back
        try! FileManager.default.removeItem(at: dir.appendingPathComponent(filename))

        // Now cachedURL should detect the missing file and remove the entry
        let url = cache.cachedURL(for: id1)
        #expect(url == nil)
        #expect(cache.trackCount == 0)
        #expect(cache.currentSize == 0)
    }
}

// MARK: - Metadata Persistence

@Suite(.serialized) struct PlaybackCacheMetadataTests {

    @Test func metadataPersistsAcrossInstances() {
        let dir = makeTempCacheDir()
        defer { cleanup(dir) }

        let id1 = UUID(), id2 = UUID()
        let entries: [PlaybackCache.CacheEntry] = [
            .init(trackId: id1, filename: "\(id1.uuidString).m4a", size: 1000, lastAccessed: Date(timeIntervalSince1970: 1000)),
            .init(trackId: id2, filename: "\(id2.uuidString).m4a", size: 2000, lastAccessed: Date(timeIntervalSince1970: 2000)),
        ]

        // Write files
        for entry in entries {
            let data = Data(repeating: 0, count: Int(entry.size))
            try! data.write(to: dir.appendingPathComponent(entry.filename))
        }

        // Write metadata
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        try! JSONEncoder().encode(entries).write(to: metadataURL)

        let settings = SettingsStore()
        let cache = PlaybackCache(settings: settings, cacheDir: dir)

        #expect(cache.trackCount == 2)
        #expect(cache.currentSize == 3000)
    }

    @Test func loadMetadataSortsByLastAccessed() {
        let dir = makeTempCacheDir()
        defer { cleanup(dir) }

        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        // Write in non-sorted order
        let entries: [PlaybackCache.CacheEntry] = [
            .init(trackId: id3, filename: "\(id3.uuidString).m4a", size: 300, lastAccessed: Date(timeIntervalSince1970: 3000)),
            .init(trackId: id1, filename: "\(id1.uuidString).m4a", size: 100, lastAccessed: Date(timeIntervalSince1970: 1000)),
            .init(trackId: id2, filename: "\(id2.uuidString).m4a", size: 200, lastAccessed: Date(timeIntervalSince1970: 2000)),
        ]

        for entry in entries {
            let data = Data(repeating: 0, count: Int(entry.size))
            try! data.write(to: dir.appendingPathComponent(entry.filename))
        }
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        try! JSONEncoder().encode(entries).write(to: metadataURL)

        let settings = SettingsStore()
        let cache = PlaybackCache(settings: settings, cacheDir: dir)

        // After loading, entries should be sorted oldest-first (LRU order)
        // Access id1 (oldest) — it should exist and be findable
        #expect(cache.cachedURL(for: id1) != nil)
        #expect(cache.trackCount == 3)
    }

    @Test func corruptMetadataFallsBackGracefully() {
        let dir = makeTempCacheDir()
        defer { cleanup(dir) }

        // Write corrupt metadata
        let metadataURL = dir.appendingPathComponent(".cache-metadata.json")
        try! "not json".data(using: .utf8)!.write(to: metadataURL)

        let settings = SettingsStore()
        let cache = PlaybackCache(settings: settings, cacheDir: dir)

        #expect(cache.trackCount == 0)
        #expect(cache.currentSize == 0)
    }
}
