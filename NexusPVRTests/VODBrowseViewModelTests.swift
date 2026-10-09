//
//  VODBrowseViewModelTests.swift
//  NexusPVRTests
//
//  The On Demand poster index (#17): paging, search, categories, and
//  switching between movies and series.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct VODBrowseViewModelTests {

    private func makeModel(_ provider: FakeVODProvider, pageSize: Int = 10) -> VODBrowseViewModel {
        VODBrowseViewModel(provider: provider, kind: .movies, pageSize: pageSize, searchDebounce: .zero)
    }

    @Test("Showing a kind loads its first page and its categories")
    func loadsFirstPage() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(25)
        provider.categories = [
            VODCategory(id: 1, name: "Action", categoryType: "movie"),
            VODCategory(id: 2, name: "Drama", categoryType: "series"),
        ]
        let model = makeModel(provider)
        await model.show(.movies)
        #expect(model.items.count == 10)
        #expect(model.totalCount == 25)
        #expect(model.categories.map(\.name) == ["Action"])
        #expect(model.error == nil)
        #expect(model.isLoading == false)
        #expect(model.isFiltered == false)
    }

    @Test("Showing the same kind again does not reload")
    func showIsIdempotent() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(5)
        let model = makeModel(provider)
        await model.show(.movies)
        await model.show(.movies)
        #expect(provider.listRequests.count == 1)
    }

    @Test("Reaching the end of the grid loads the next page, once")
    func loadsMore() async throws {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(25)
        let model = makeModel(provider)
        await model.show(.movies)

        // Far from the end: nothing happens.
        await model.loadMoreIfNeeded(after: model.items[0])
        #expect(model.items.count == 10)

        await model.loadMoreIfNeeded(after: try #require(model.items.last))
        #expect(model.items.count == 20)
        await model.loadMoreIfNeeded(after: try #require(model.items.last))
        #expect(model.items.count == 25)
        #expect(Set(model.items.map(\.id)).count == 25)

        // Everything is loaded; no further request goes out.
        let requests = provider.listRequests.count
        await model.loadMoreIfNeeded(after: try #require(model.items.last))
        #expect(provider.listRequests.count == requests)
        #expect(provider.listRequests.map(\.page) == [1, 2, 3])
    }

    @Test("A failed next page keeps what is shown and can be retried")
    func loadMoreFailureKeepsItems() async throws {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(25)
        let model = makeModel(provider)
        await model.show(.movies)
        provider.nextError = PVRClientError.invalidResponse
        await model.loadMoreIfNeeded(after: try #require(model.items.last))
        #expect(model.items.count == 10)
        #expect(model.error == nil)
        await model.loadMoreIfNeeded(after: try #require(model.items.last))
        #expect(model.items.count == 20)
    }

    @Test("Typing searches the server after the pause, from page one")
    func search() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(25)
        let model = makeModel(provider)
        await model.show(.movies)
        model.searchText = " 02 "
        await model.searchTextChanged().value
        #expect(provider.listRequests.last?.search == "02")
        #expect(provider.listRequests.last?.page == 1)
        #expect(model.items.allSatisfy { $0.name.contains("02") })
        #expect(model.totalCount == model.items.count)
        #expect(model.isFiltered)
    }

    @Test("Only the last keystroke's search reaches the server")
    func searchDebounces() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(25)
        let model = VODBrowseViewModel(provider: provider, kind: .movies, pageSize: 10, searchDebounce: .milliseconds(50))
        await model.show(.movies)
        model.searchText = "0"
        let first = model.searchTextChanged()
        model.searchText = "02"
        let second = model.searchTextChanged()
        await first.value
        await second.value
        #expect(provider.listRequests.compactMap(\.search) == ["02"])
    }

    @Test("Choosing a category reloads with its filter; choosing it again does nothing")
    func category() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(5)
        let model = makeModel(provider)
        await model.show(.movies)
        let action = VODCategory(id: 1, name: "Action", categoryType: "movie")
        await model.selectCategory(action)
        #expect(provider.listRequests.last?.category == "Action|movie")
        #expect(model.isFiltered)
        let requests = provider.listRequests.count
        await model.selectCategory(action)
        #expect(provider.listRequests.count == requests)
        await model.selectCategory(nil)
        #expect(provider.listRequests.last?.category == nil)
    }

    @Test("Switching kinds starts over without the search or category")
    func switchingKinds() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(5)
            + [VODItem(itemId: 1, uuid: "s1", name: "A Series", kind: .series)]
        let model = makeModel(provider)
        await model.show(.movies)
        model.searchText = "Movie"
        await model.selectCategory(VODCategory(id: 1, name: "Action", categoryType: "movie"))

        await model.show(.series)
        #expect(model.kind == .series)
        #expect(model.searchText.isEmpty)
        #expect(model.selectedCategory == nil)
        #expect(model.items.map(\.name) == ["A Series"])
        #expect(provider.listRequests.last?.search == nil)
        #expect(provider.listRequests.last?.category == nil)
    }

    @Test("A failed load reports the error and shows nothing")
    func loadFailure() async {
        let provider = FakeVODProvider()
        provider.library = FakeVODProvider.movies(5)
        provider.nextError = PVRClientError.invalidResponse
        let model = makeModel(provider)
        await model.show(.movies)
        #expect(model.items.isEmpty)
        #expect(model.error != nil)

        await model.reload()
        #expect(model.error == nil)
        #expect(model.items.count == 5)
    }
}
