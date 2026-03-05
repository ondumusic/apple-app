import Foundation
import SwiftData

@Observable
final class OfflineStore {
    @ObservationIgnored let modelContainer: ModelContainer

    init() throws {
        let schema = Schema([DownloadedArtist.self, DownloadedAlbum.self, DownloadedTrack.self])
        modelContainer = try ModelContainer(for: schema)
    }

    var modelContext: ModelContext { modelContainer.mainContext }

    func isDownloaded(trackId: UUID) -> Bool {
        let descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == trackId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    func localURL(for trackId: UUID) -> URL? {
        var descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == trackId })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.localFileURL
    }

    func downloadedArtists() -> [DownloadedArtist] {
        let descriptor = FetchDescriptor<DownloadedArtist>(sortBy: [SortDescriptor(\.name)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func ensureArtist(from artist: Artist) -> DownloadedArtist {
        let artistId = artist.id
        var descriptor = FetchDescriptor<DownloadedArtist>(predicate: #Predicate { $0.id == artistId })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first { return existing }
        let new = DownloadedArtist(id: artist.id, name: artist.name)
        modelContext.insert(new)
        return new
    }

    func ensureAlbum(from album: Album, artist: DownloadedArtist) -> DownloadedAlbum {
        let albumId = album.id
        var descriptor = FetchDescriptor<DownloadedAlbum>(predicate: #Predicate { $0.id == albumId })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first { return existing }
        let new = DownloadedAlbum(
            id: album.id, artistId: album.artistId, name: album.name,
            releaseYear: album.releaseYear, artworkUrl: album.artworkUrl
        )
        new.artist = artist
        modelContext.insert(new)
        return new
    }

    func insertTrack(_ track: Track, localFileURL: URL, album: DownloadedAlbum) {
        let downloaded = DownloadedTrack(from: track, localFileURL: localFileURL)
        downloaded.album = album
        modelContext.insert(downloaded)
        try? modelContext.save()
    }

    func deleteTrack(trackId: UUID) {
        var descriptor = FetchDescriptor<DownloadedTrack>(predicate: #Predicate { $0.id == trackId })
        descriptor.fetchLimit = 1
        guard let track = try? modelContext.fetch(descriptor).first else { return }
        try? FileManager.default.removeItem(at: track.localFileURL)
        let album = track.album
        modelContext.delete(track)
        if let album, album.tracks.count <= 1 {
            let artist = album.artist
            modelContext.delete(album)
            if let artist, artist.albums.count <= 1 {
                modelContext.delete(artist)
            }
        }
        try? modelContext.save()
    }

    func deleteAlbum(albumId: UUID) {
        let id = albumId
        var descriptor = FetchDescriptor<DownloadedAlbum>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let album = try? modelContext.fetch(descriptor).first else { return }
        for track in album.tracks {
            try? FileManager.default.removeItem(at: track.localFileURL)
        }
        let artist = album.artist
        modelContext.delete(album)
        if let artist, artist.albums.count <= 1 {
            modelContext.delete(artist)
        }
        try? modelContext.save()
    }

    func deleteArtist(artistId: UUID) {
        let id = artistId
        var descriptor = FetchDescriptor<DownloadedArtist>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let artist = try? modelContext.fetch(descriptor).first else { return }
        for album in artist.albums {
            for track in album.tracks {
                try? FileManager.default.removeItem(at: track.localFileURL)
            }
        }
        modelContext.delete(artist)
        try? modelContext.save()
    }
}
