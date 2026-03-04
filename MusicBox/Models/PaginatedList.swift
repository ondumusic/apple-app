import Foundation

nonisolated struct PaginatedItem<T: Sendable>: Identifiable, Sendable {
    let index: Int
    let value: T?

    // ID changes when item loads, forcing SwiftUI to re-render the row
    var id: String { "\(index):\(value == nil ? "p" : "v")" }
}

// Shared mutable box to pass the page number to the closure
// without relying on closure parameter passing (workaround for Swift compiler bug)
final class PageRequest {
    var page: Int = 1
}

@Observable
final class PaginatedList<T: Decodable & Sendable> {
    private(set) var items: [T?] = []
    private(set) var totalEntries = 0
    private(set) var totalPages = 0
    private(set) var pageSize = 0
    @ObservationIgnored
    private var loadedPages: Set<Int> = []
    @ObservationIgnored
    private var loadingPages: Set<Int> = []
    private(set) var error: String?

    @ObservationIgnored
    private let pageRequest = PageRequest()
    @ObservationIgnored
    private let fetchPage: () async throws -> Page<T>

    /// The closure should read `request.page` to get the current page number.
    init(fetch: @escaping (PageRequest) async throws -> Page<T>) {
        let request = pageRequest
        self.fetchPage = { try await fetch(request) }
    }

    var isEmpty: Bool { items.isEmpty }
    var hasLoaded: Bool { !loadedPages.isEmpty }

    var identifiableItems: [PaginatedItem<T>] {
        items.enumerated().map { PaginatedItem(index: $0.offset, value: $0.element) }
    }

    func loadInitialIfNeeded() {
        guard !hasLoaded, loadingPages.isEmpty else { return }
        Task { await loadPage(1) }
    }

    func reload() async {
        loadedPages.removeAll()
        loadingPages.removeAll()
        items = []
        totalEntries = 0
        pageSize = 0
        error = nil
        await loadPage(1)
    }

    func itemAppeared(at index: Int) {
        guard pageSize > 0 else { return }
        let page = (index / pageSize) + 1
        guard page <= totalPages,
              !loadedPages.contains(page),
              !loadingPages.contains(page) else { return }
        Task { await loadPage(page) }
    }

    private func loadPage(_ page: Int) async {
        guard !loadingPages.contains(page) else { return }
        loadingPages.insert(page)

        do {
            pageRequest.page = page
            let result = try await fetchPage()

            if !hasLoaded || totalEntries != result.totalEntries {
                totalEntries = result.totalEntries
                totalPages = result.totalPages
                pageSize = result.pageSize
            }

            // Build new array and assign atomically so @Observable detects the change
            var newItems = items
            if newItems.count < totalEntries {
                newItems += Array(repeating: nil, count: totalEntries - newItems.count)
            }

            let startIndex = (page - 1) * pageSize
            for (offset, entry) in result.entries.enumerated() {
                let idx = startIndex + offset
                if idx < newItems.count {
                    newItems[idx] = entry
                }
            }

            items = newItems

            loadedPages.insert(page)
            loadingPages.remove(page)
            error = nil
        } catch is CancellationError {
            loadingPages.remove(page)
        } catch let urlError as URLError where urlError.code == .cancelled {
            loadingPages.remove(page)
        } catch {
            loadingPages.remove(page)
            self.error = error.localizedDescription
        }
    }
}
