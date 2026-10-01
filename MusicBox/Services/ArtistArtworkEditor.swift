import Foundation

/// Uploading and removing an artist's picture.
///
/// Shared because the only platform-specific part is how the image gets picked — a panel
/// on the Mac, the photo library on a phone. What happens afterwards is the same: send it,
/// and write what comes back into the library so the circle changes now rather than at the
/// next sync.
@MainActor
struct ArtistArtworkEditor {
    let api: APIService?
    let musicLibrary: MusicLibrary

    nonisolated enum Failure: Error, Equatable {
        case notSignedIn
        case notAnImage
        case tooLarge
        case failed(String)

        /// What to put in front of someone. The two the server names are worth saying
        /// plainly; anything else is the underlying error, which is usually a network
        /// one and already reads as a sentence.
        var message: LocalizedStringResource {
            switch self {
            case .notSignedIn: "Not signed in."
            case .notAnImage: "That file isn't an image MusicBox can read."
            case .tooLarge: "That image is too large for the server to accept."
            case .failed(let detail): "Couldn't update the artwork. \(detail)"
            }
        }
    }

    func upload(artistId: UUID, from fileURL: URL) async throws(Failure) {
        let prepared: ArtworkUpload.Prepared
        do {
            prepared = try ArtworkUpload.prepare(contentsOf: fileURL)
        } catch {
            throw Failure.notAnImage
        }
        try await send(artistId: artistId, prepared: prepared)
    }

    func upload(artistId: UUID, data: Data) async throws(Failure) {
        let prepared: ArtworkUpload.Prepared
        do {
            prepared = try ArtworkUpload.prepare(data: data)
        } catch {
            throw Failure.notAnImage
        }
        try await send(artistId: artistId, prepared: prepared)
    }

    func remove(artistId: UUID) async throws(Failure) {
        guard let api else { throw Failure.notSignedIn }
        do {
            let artist = try await api.deleteArtistArtwork(artistId: artistId)
            musicLibrary.setArtistArtwork(artist.artwork, for: artistId)
        } catch {
            throw Self.translate(error)
        }
    }

    private func send(artistId: UUID, prepared: ArtworkUpload.Prepared) async throws(Failure) {
        guard let api else { throw Failure.notSignedIn }
        do {
            let artist = try await api.uploadArtistArtwork(
                artistId: artistId, imageData: prepared.data,
                filename: prepared.filename, mimeType: prepared.mimeType)
            musicLibrary.setArtistArtwork(artist.artwork, for: artistId)
        } catch {
            throw Self.translate(error)
        }
    }

    private static func translate(_ error: Error) -> Failure {
        if let artwork = error as? APIService.ArtworkError {
            switch artwork {
            case .notAnImage: return .notAnImage
            case .tooLarge: return .tooLarge
            }
        }
        return .failed(error.localizedDescription)
    }
}
