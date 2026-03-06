import Foundation

nonisolated struct PaginatedItem<T: Sendable>: Identifiable, Sendable {
    let index: Int
    let value: T?
    let isLoaded: Bool

    // ID changes when item loads, forcing SwiftUI to re-render the row
    var id: Int { isLoaded ? index : -(index + 1) }

    init(index: Int, value: T?) {
        self.index = index
        self.value = value
        self.isLoaded = value != nil
    }
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

    private(set) var identifiableItems: [PaginatedItem<T>] = []

    private func rebuildIdentifiableItems() {
        identifiableItems = items.enumerated().map { PaginatedItem(index: $0.offset, value: $0.element) }
    }

    func loadInitialIfNeeded() {
        guard !hasLoaded, loadingPages.isEmpty else { return }
        Task { await loadPage(1) }
    }

    func reload() async {
        loadedPages.removeAll()
        loadingPages.removeAll()
        items = []
        identifiableItems = []
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

    /// Loads all remaining pages sequentially after the initial page.
    func loadAllPages() {
        guard hasLoaded, totalPages > 1 else { return }
        Task {
            for page in 2...totalPages {
                guard !loadedPages.contains(page) else { continue }
                await loadPage(page)
            }
        }
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
            rebuildIdentifiableItems()

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
