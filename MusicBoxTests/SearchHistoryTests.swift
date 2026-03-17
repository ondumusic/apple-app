import Foundation
import Testing
@testable import MusicBox

private func makeItem(kind: SearchHistoryItem.Kind = .artist, name: String = "Test",
                      id: UUID = UUID()) -> SearchHistoryItem {
    SearchHistoryItem(id: id, kind: kind, name: name)
}

/// Serialized because all tests share UserDefaults.standard.
@Suite(.serialized)
struct SearchHistoryTests {

    private func clearHistory() {
        UserDefaults.standard.removeObject(forKey: "searchHistory")
    }

    // MARK: - Add

    @Test func addInsertsAtFront() {
        clearHistory()
        let history = SearchHistory()
        let item = makeItem(name: "Beatles")
        history.add(item)

        #expect(history.items.count == 1)
        #expect(history.items[0].name == "Beatles")
        clearHistory()
    }

    @Test func addDeduplicatesByIdAndKind() {
        clearHistory()
        let history = SearchHistory()
        let id = UUID()
        history.add(makeItem(kind: .artist, name: "Old", id: id))
        history.add(makeItem(kind: .artist, name: "New", id: id))

        #expect(history.items.count == 1)
        #expect(history.items[0].name == "New")
        clearHistory()
    }

    @Test func addSameIdDifferentKindKeepsBoth() {
        clearHistory()
        let history = SearchHistory()
        let id = UUID()
        history.add(makeItem(kind: .artist, name: "Artist", id: id))
        history.add(makeItem(kind: .album, name: "Album", id: id))

        #expect(history.items.count == 2)
        clearHistory()
    }

    @Test func addCapsAt20() {
        clearHistory()
        let history = SearchHistory()
        for i in 0..<25 {
            history.add(makeItem(name: "Item \(i)"))
        }

        #expect(history.items.count == 20)
        #expect(history.items[0].name == "Item 24") // Most recent first
        clearHistory()
    }

    // MARK: - Remove

    @Test func removeDeletesItem() {
        clearHistory()
        let history = SearchHistory()
        let item = makeItem(name: "ToRemove")
        history.add(item)
        history.remove(item)

        #expect(history.items.isEmpty)
        clearHistory()
    }

    // MARK: - Clear

    @Test func clearRemovesAll() {
        clearHistory()
        let history = SearchHistory()
        history.add(makeItem(name: "A"))
        history.add(makeItem(name: "B"))
        history.clear()

        #expect(history.items.isEmpty)
        clearHistory()
    }

    // MARK: - Persistence

    @Test func persistsToUserDefaults() {
        clearHistory()
        let history = SearchHistory()
        history.add(makeItem(name: "Persisted"))

        // New instance should load from UserDefaults
        let history2 = SearchHistory()
        #expect(history2.items.count == 1)
        #expect(history2.items[0].name == "Persisted")
        clearHistory()
    }
}

// MARK: - SearchHistoryItem

struct SearchHistoryItemTests {

    @Test func displayKind() {
        #expect(makeItem(kind: .artist).displayKind == "Artist")
        #expect(makeItem(kind: .album).displayKind == "Album")
        #expect(makeItem(kind: .song).displayKind == "Song")
    }
}
