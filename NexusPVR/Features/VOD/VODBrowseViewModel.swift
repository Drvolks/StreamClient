//
//  VODBrowseViewModel.swift
//  DispatcherPVR
//
//  The On Demand poster index: one kind (movies or series) at a time,
//  loaded a page at a time as the grid scrolls, narrowed by search and
//  category (#17)
//

import Foundation
import Combine

@MainActor
final class VODBrowseViewModel: ObservableObject {
    @Published private(set) var kind: VODKind
    @Published private(set) var items: [VODItem] = []
    /// Size of the filtered library on the server, not of what is loaded.
    @Published private(set) var totalCount = 0
    @Published private(set) var categories: [VODCategory] = []
    @Published private(set) var selectedCategory: VODCategory?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    /// Bound to the search field; call `searchTextChanged()` after edits.
    @Published var searchText = ""

    private let provider: any VODProviding
    private let pageSize: Int
    private let searchDebounce: Duration
    private var nextPage = 1
    private var hasMore = false
    private var hasLoaded = false
    /// Bumped by every reload, so a slow response for an old query is dropped.
    private var generation = 0
    private var searchTask: Task<Void, Never>?

    init(
        provider: any VODProviding,
        kind: VODKind = .movies,
        pageSize: Int = 60,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.provider = provider
        self.kind = kind
        self.pageSize = pageSize
        self.searchDebounce = searchDebounce
    }

    var isFiltered: Bool {
        selectedCategory != nil || !trimmedSearch.isEmpty
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shows `kind`. Switching kinds starts over: search and category belong
    /// to the library they were typed in.
    func show(_ newKind: VODKind) async {
        guard newKind != kind || !hasLoaded else { return }
        searchTask?.cancel()
        kind = newKind
        searchText = ""
        selectedCategory = nil
        categories = []
        items = []
        totalCount = 0
        await reload()
        await loadCategories()
    }

    /// Loads the first page for the current kind, search and category.
    func reload() async {
        generation += 1
        let current = generation
        hasLoaded = true
        isLoading = true
        error = nil
        defer { if current == generation { isLoading = false } }
        do {
            let page = try await provider.getVODItems(
                kind: kind,
                page: 1,
                pageSize: pageSize,
                search: trimmedSearch.isEmpty ? nil : trimmedSearch,
                category: selectedCategory?.filterValue
            )
            guard current == generation else { return }
            items = page.items
            totalCount = page.totalCount
            hasMore = page.hasMore
            nextPage = 2
        } catch {
            guard current == generation else { return }
            items = []
            totalCount = 0
            hasMore = false
            self.error = error.localizedDescription
        }
    }

    /// Call when `item` scrolls into view; fetches the next page once the
    /// grid is near its end.
    func loadMoreIfNeeded(after item: VODItem) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index >= items.count - max(pageSize / 4, 1) else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await provider.getVODItems(
                kind: kind,
                page: nextPage,
                pageSize: pageSize,
                search: trimmedSearch.isEmpty ? nil : trimmedSearch,
                category: selectedCategory?.filterValue
            )
            guard current == generation else { return }
            // A library that changed between pages can repeat an item.
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            totalCount = page.totalCount
            hasMore = page.hasMore
            nextPage += 1
        } catch {
            // Keep what is shown; scrolling again retries.
        }
    }

    func selectCategory(_ category: VODCategory?) async {
        guard category != selectedCategory else { return }
        selectedCategory = category
        await reload()
    }

    /// Reloads once typing pauses. The returned task finishes when that
    /// reload has, or when further typing replaced it.
    @discardableResult
    func searchTextChanged() -> Task<Void, Never> {
        searchTask?.cancel()
        let task = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
        searchTask = task
        return task
    }

    private func loadCategories() async {
        let requested = kind
        // Categories are a convenience; the library works without them.
        let loaded = (try? await provider.getVODCategories(kind: requested)) ?? []
        guard requested == kind else { return }
        categories = loaded
    }
}
