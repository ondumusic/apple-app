import SwiftUI

struct AlbumListView: View {
    @Environment(AuthService.self) private var auth

    @State private var albums: [Album] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if album == albums.last {
                            loadMore()
                        }
                    }
                }
            }
            .padding()

            if isLoading {
                ProgressView()
                    .padding()
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("Albums")
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
        .task {
            if albums.isEmpty {
                await fetchPage(1)
            }
        }
        .refreshable {
            albums = []
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
            let result = try await api.fetchAllAlbums(page: page)
            if page == 1 {
                albums = result.entries
            } else {
                albums.append(contentsOf: result.entries)
            }
            currentPage = result.pageNumber
            totalPages = result.totalPages
        } catch {
            self.error = error.localizedDescription
        }
    }
}
