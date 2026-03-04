import SwiftUI

struct ArtistListView: View {
    @Environment(AuthService.self) private var auth

    @State private var artists: [Artist] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(artists) { artist in
                NavigationLink(value: artist) {
                    ArtistCard(artist: artist)
                }
                .onAppear {
                    if artist == artists.last {
                        loadMore()
                    }
                }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("Artists")
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .task {
            if artists.isEmpty {
                await fetchPage(1)
            }
        }
        .refreshable {
            artists = []
            currentPage = 1
            totalPages = 1
            await fetchPage(1)
        }
    }

    private func loadMore() {
        guard currentPage < totalPages, !isLoading else { return }
        Task { await fetchPage(currentPage + 1) }
    }

    private func fetchPage(_ page: Int) async {
        guard let api = auth.apiService, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await api.fetchArtists(page: page)
            if page == 1 {
                artists = result.entries
            } else {
                artists.append(contentsOf: result.entries)
            }
            currentPage = result.pageNumber
            totalPages = result.totalPages
        } catch {
            self.error = error.localizedDescription
        }
    }
}
