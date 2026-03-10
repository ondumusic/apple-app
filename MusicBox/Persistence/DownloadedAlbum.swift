import Foundation
import SwiftData

@Model
nonisolated class DownloadedAlbum {
    @Attribute(.unique) var id: UUID
    var artistId: UUID
    var name: String
    var releaseYear: Int?
    var artworkUrl: URL?
    var artist: DownloadedArtist?
    

    @Relationship(deleteRule: .cascade, inverse: \DownloadedTrack.album)
    var tracks: [DownloadedTrack] = []

    init(id: UUID, artistId: UUID, name: String, releaseYear: Int?, artworkUrl: URL?) {
        self.id = id
        self.artistId = artistId
        self.name = name
        self.releaseYear = releaseYear
        self.artworkUrl = artworkUrl
    }
}
