import Foundation
import SwiftData

@Model
nonisolated class DownloadedArtist {
    @Attribute(.unique) var id: UUID
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \DownloadedAlbum.artist)
    var albums: [DownloadedAlbum] = []

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
