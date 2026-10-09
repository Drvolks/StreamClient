//
//  DemoVODLibraryTests.swift
//  NexusPVRTests
//
//  The demo On Demand library (#17): it has to behave like the server's
//  list endpoints, and offer series with more than one season.
//

import Testing
import Foundation
@testable import NextPVR

struct DemoVODLibraryTests {

    private func all(_ kind: VODKind) -> [VODItem] {
        DemoVODLibrary.page(kind: kind, page: 1, pageSize: 100, search: nil, category: nil).items
    }

    @Test("The demo library has both movies and series")
    func counts() {
        #expect(DemoVODLibrary.counts.movies > 0)
        #expect(DemoVODLibrary.counts.series > 0)
        #expect(all(.movies).count == DemoVODLibrary.counts.movies)
        #expect(all(.series).count == DemoVODLibrary.counts.series)
    }

    @Test("Every title has a unique id and uuid, a poster and something to say")
    func titlesAreComplete() {
        let titles = DemoVODLibrary.titles
        #expect(Set(titles.map(\.id)).count == titles.count)
        #expect(Set(titles.map(\.uuid)).count == titles.count)
        #expect(titles.allSatisfy { !$0.name.isEmpty && !$0.plot.isEmpty && !$0.poster.isEmpty && !$0.backdrop.isEmpty })
    }

    @Test("Items are listed by name and stamped with their kind")
    func listOrderAndKind() {
        let movies = all(.movies)
        #expect(movies.map(\.name) == movies.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(movies.allSatisfy { $0.kind == .movies && $0.durationSecs != nil && $0.episodeCount == nil })
        #expect(all(.series).allSatisfy { $0.kind == .series && ($0.episodeCount ?? 0) > 0 })
    }

    @Test("Pages don't overlap and report whether more follow")
    func pagination() {
        let first = DemoVODLibrary.page(kind: .movies, page: 1, pageSize: 4, search: nil, category: nil)
        let second = DemoVODLibrary.page(kind: .movies, page: 2, pageSize: 4, search: nil, category: nil)
        let beyond = DemoVODLibrary.page(kind: .movies, page: 99, pageSize: 4, search: nil, category: nil)
        #expect(first.items.count == 4)
        #expect(first.hasMore)
        #expect(first.totalCount == DemoVODLibrary.counts.movies)
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        #expect(beyond.items.isEmpty)
        #expect(beyond.hasMore == false)
    }

    @Test("Search matches name, plot and genre, ignoring case")
    func search() {
        let byName = DemoVODLibrary.page(kind: .movies, page: 1, pageSize: 50, search: "ONION", category: nil)
        let byGenre = DemoVODLibrary.page(kind: .movies, page: 1, pageSize: 50, search: "western", category: nil)
        let nothing = DemoVODLibrary.page(kind: .movies, page: 1, pageSize: 50, search: "zzzz", category: nil)
        #expect(byName.items.map(\.name) == ["Lord of the Onion Rings"])
        #expect(byGenre.items.map(\.name) == ["A Fistful of Coupons"])
        #expect(nothing.items.isEmpty)
        #expect(nothing.totalCount == 0)
    }

    @Test("Each category lists exactly its own titles")
    func categories() {
        for kind in VODKind.allCases {
            let categories = DemoVODLibrary.categories(kind: kind)
            #expect(!categories.isEmpty)
            #expect(Set(categories.map(\.id)).count == categories.count)
            var seen = 0
            for category in categories {
                #expect(category.categoryType == kind.categoryType)
                let page = DemoVODLibrary.page(kind: kind, page: 1, pageSize: 100, search: nil, category: category.filterValue)
                #expect(!page.items.isEmpty)
                seen += page.items.count
            }
            #expect(seen == DemoVODLibrary.counts.count(for: kind))
        }
    }

    @Test("Every movie has a detail page matching its list entry")
    func movieDetails() throws {
        for item in all(.movies) {
            let detail = try #require(DemoVODLibrary.movieDetail(id: item.itemId))
            #expect(detail.uuid == item.uuid)
            #expect(detail.name == item.name)
            #expect(detail.durationSecs == item.durationSecs)
            #expect(detail.plot?.isEmpty == false)
            #expect(detail.director?.isEmpty == false)
        }
        #expect(DemoVODLibrary.movieDetail(id: 1) == nil)
    }

    @Test("Every series has several seasons of uniquely identified episodes")
    func seriesDetails() throws {
        var episodeIDs = Set<Int>()
        var episodeUUIDs = Set<String>()
        for item in all(.series) {
            let detail = try #require(DemoVODLibrary.seriesDetail(id: item.itemId))
            #expect(detail.seasons.count >= 2)
            #expect(detail.seasons.map(\.number) == Array(1...detail.seasons.count))
            #expect(detail.episodeCount == item.episodeCount)
            for season in detail.seasons {
                #expect(season.episodes.map(\.episodeNumber) == Array(1...season.episodes.count))
                for episode in season.episodes {
                    #expect(episodeIDs.insert(episode.id).inserted)
                    #expect(episodeUUIDs.insert(episode.uuid).inserted)
                    #expect(!episode.name.isEmpty)
                    #expect(episode.description?.isEmpty == false)
                    #expect((episode.durationSecs ?? 0) > 0)
                    #expect(episode.metaLine.contains("min"))
                }
            }
        }
        #expect(DemoVODLibrary.seriesDetail(id: 1) == nil)
    }

    @Test("A title can be found by name for --demo-vod")
    func itemNamed() {
        #expect(DemoVODLibrary.item(named: "game of thermostats")?.kind == .series)
        #expect(DemoVODLibrary.item(named: "Jurassic Parking")?.kind == .movies)
        #expect(DemoVODLibrary.item(named: "Not a Title") == nil)
    }

    @Test("Seeded watch state refers to real movies and episodes")
    func seededProgress() {
        var known = Set(DemoVODLibrary.titles.filter { $0.kind == .movies }.map(\.uuid))
        for item in all(.series) {
            known.formUnion(DemoVODLibrary.seriesDetail(id: item.itemId)?.allEpisodes.map(\.uuid) ?? [])
        }
        let seeded = DemoVODLibrary.seededProgress
        #expect(!seeded.isEmpty)
        #expect(seeded.keys.allSatisfy(known.contains))
        #expect(seeded.values.contains { $0.watchState == .watched })
        #expect(seeded.values.contains { $0.hasResumePosition })
    }

    @Test("Artwork that isn't in the bundle resolves to nothing")
    func missingArtwork() {
        #expect(DemoVODLibrary.imageURL(named: "demo_vod_does_not_exist.jpg") == nil)
    }
}
