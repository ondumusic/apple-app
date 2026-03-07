import Foundation

@Observable
final class SearchHistory {
    private static let key = "searchHistory"
    private static let maxItems = 20

    private(set) var items: [SearchHistoryItem] = []

    init() {
        load()
    }

    func add(_ item: SearchHistoryItem) {
        items.removeAll { $0.id == item.id && $0.kind == item.kind }
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

struct SearchHistoryItem: Codable, Identifiable {
    enum Kind: String, Codable {
        case artist, album, song
    }

    var id: UUID
    var kind: Kind
    var name: String
    var subtitle: String?
    var artworkUrl: URL?
    /// For navigation: the artist/album ID or the artist ID for a song
    var artistId: UUID?
    var albumId: UUID?

    var displayKind: String {
        switch kind {
        case .artist: "Artist"
        case .album: "Album"
        case .song: "Song"
        }
    }
}
