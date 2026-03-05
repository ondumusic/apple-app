import SwiftUI

struct ArtistListView: View {
    @Environment(LibraryViewModel.self) private var library
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        let list = library.artists
        List(list.identifiableItems) { item in
            if let artist = item.value {
                NavigationLink(value: artist) {
                    ArtistCard(artist: artist)
                }
                .onAppear { list.itemAppeared(at: item.index) }
            } else {
                HStack(spacing: 12) {
                    Circle().fill(.quaternary).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 60, height: 12)
                    }
                    Spacer()
                }
                .onAppear { list.itemAppeared(at: item.index) }
            }
        }
        .scrollPosition($scrollPosition)
        .navigationTitle("Artists")
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
        .onAppear { list.loadInitialIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToTop)) { _ in
            withAnimation { scrollPosition.scrollTo(edge: .top) }
        }
        .overlay {
            if let error = list.error, list.isEmpty {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}
