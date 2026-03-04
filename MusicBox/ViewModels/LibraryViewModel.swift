import Foundation

@Observable
final class LibraryViewModel {
    let api: APIService

    private(set) var artists: PaginatedList<Artist>
    private(set) var albums: PaginatedList<Album>
    private(set) var tracks: PaginatedList<Track>

    init(api: APIService) {
        self.api = api

        self.artists = PaginatedList { request in
            try await api.fetchArtists(page: request.page)
        }

        self.albums = PaginatedList { request in
            try await api.fetchAllAlbums(page: request.page)
        }

        self.tracks = PaginatedList { request in
            try await api.fetchTracks(page: request.page)
        }
    }

    func albumList(for artist: Artist) -> PaginatedList<Album> {
        PaginatedList { [api] request in
            try await api.fetchAlbums(for: artist.id, page: request.page)
        }
    }
}
