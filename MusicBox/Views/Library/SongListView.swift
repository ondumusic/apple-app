import SwiftUI

struct SongListView: View {
    @Environment(AuthService.self) private var auth

    @State private var tracks: [Track] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            ForEach(tracks) { track in
                TrackRow(track: track, showArtist: true, showNumber: false)
                    .onAppear {
                        if track == tracks.last {
                            loadMore()
                        }
                    }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Songs")
        .task {
            if tracks.isEmpty {
                await fetchPage(1)
            }
        }
        .refreshable {
            tracks = []
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
            let result = try await api.fetchTracks(page: page)
            if page == 1 {
                tracks = result.entries
            } else {
                tracks.append(contentsOf: result.entries)
            }
            currentPage = result.pageNumber
            totalPages = result.totalPages
        } catch {
            self.error = error.localizedDescription
        }
    }
}
