//
//  SearchViewModelTests.swift
//  NexusPVRTests
//
//  Tests for SearchViewModel: searchText behavior, hasSearched state,
//  result management, and guard conditions.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct SearchViewModelTests {

    @Test("Initial state: searchText empty, results empty, not loading")
    func initialState() {
        let vm = SearchViewModel()
        #expect(vm.searchText.isEmpty)
        #expect(vm.results.isEmpty)
        #expect(vm.isLoading == false)
        #expect(vm.error == nil)
        #expect(vm.hasSearched == false)
    }

    @Test("search clears results and hasSearched when text < 2 chars")
    func searchClearsForShortText() {
        let vm = SearchViewModel()
        let ch = Channel(id: 1, name: "Test", number: 1)
        let now = Int(Date().timeIntervalSince1970)
        let prog = Program(id: 1, name: "X", subtitle: nil, desc: nil, start: now, end: now + 3600, genres: nil, channelId: 1)
        vm.results = [SearchResult(program: prog, channel: ch)]
        vm.hasSearched = true
        vm.searchText = "A"
        vm.search()
        #expect(vm.results.isEmpty)
        #expect(vm.hasSearched == false)
    }

    #if !os(tvOS)
    @Test("search does not call EPGCache when cache is nil")
    func searchNoCacheDoesNothing() {
        let vm = SearchViewModel()
        vm.epgCache = nil
        vm.searchText = "news"
        vm.search()
        #expect(vm.results.isEmpty)
    }

    @Test("search does not call EPGCache when cache not loaded")
    func searchCacheNotLoaded() {
        let cache = EPGCache()
        let vm = SearchViewModel()
        vm.epgCache = cache
        vm.searchText = "sports"
        vm.search()
        #expect(vm.results.isEmpty)
    }
    #endif

    @Test("hasSearched remains false when searchText is empty")
    func hasSearchedFalseForEmpty() {
        let vm = SearchViewModel()
        vm.searchText = ""
        vm.search()
        #expect(vm.hasSearched == false)
    }

    @Test("hasSearched set to false when cache not loaded")
    func hasSearchedFalseWhenCacheNotLoaded() {
        let vm = SearchViewModel()
        let cache = EPGCache()
        vm.epgCache = cache
        vm.searchText = "query"
        vm.search()
        #expect(vm.hasSearched == false)
    }

    @Test("SearchResult id combines program and channel IDs")
    func searchResultId() {
        let ch = Channel(id: 5, name: "Test", number: 1)
        let now = Int(Date().timeIntervalSince1970)
        let prog = Program(id: 42, name: "Test", subtitle: nil, desc: nil, start: now, end: now + 3600, genres: nil, channelId: 5)
        let result = SearchResult(program: prog, channel: ch)
        #expect(result.id == "42-5")
        #expect(result.program.id == 42)
        #expect(result.channel.id == 5)
    }

    @Test("MatchingProgram id combines program and channel IDs")
    func matchingProgramId() {
        let ch = Channel(id: 3, name: "Test", number: 1)
        let now = Int(Date().timeIntervalSince1970)
        let prog = Program(id: 99, name: "Test", subtitle: nil, desc: nil, start: now, end: now + 3600, genres: nil, channelId: 3)
        let match = MatchingProgram(program: prog, channel: ch, matchedKeyword: "foo")
        #expect(match.id == "99-3")
        #expect(match.matchedKeyword == "foo")
    }

    @Test("MatchingProgram scheduledKeyword constant")
    func matchingProgramScheduledKeyword() {
        #expect(MatchingProgram.scheduledKeyword == "Scheduled")
    }
}
