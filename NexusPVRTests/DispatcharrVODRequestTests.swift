//
//  DispatcharrVODRequestTests.swift
//  NexusPVRTests
//
//  URL building for the Dispatcharr VOD API (#17).
//

import Testing
import Foundation
@testable import NextPVR

struct DispatcharrVODRequestTests {

    private let base = "http://dispatcharr.local:9191"

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test("Movies and series list from their own endpoints, ordered by name")
    func listPaths() {
        let movies = DispatcharrVODRequest.listURL(baseURL: base, kind: .movies, page: 2, pageSize: 60)
        let series = DispatcharrVODRequest.listURL(baseURL: base, kind: .series, page: 1, pageSize: 60)
        #expect(movies?.absoluteString.hasPrefix("\(base)/api/vod/movies/?") == true)
        #expect(series?.absoluteString.hasPrefix("\(base)/api/vod/series/?") == true)
        #expect(query(movies) == ["page": "2", "page_size": "60", "ordering": "name"])
    }

    @Test("Search and category are sent only when set, and survive encoding")
    func listFilters() {
        let url = DispatcharrVODRequest.listURL(
            baseURL: base, kind: .movies, page: 1, pageSize: 20,
            search: "  rock & roll ", category: "Sci-Fi & Fantasy|movie"
        )
        #expect(query(url)["search"] == "rock & roll")
        #expect(query(url)["category"] == "Sci-Fi & Fantasy|movie")

        let blank = DispatcharrVODRequest.listURL(baseURL: base, kind: .movies, page: 1, pageSize: 20, search: "   ", category: "")
        #expect(query(blank)["search"] == nil)
        #expect(query(blank)["category"] == nil)
    }

    @Test("Page and page size are clamped to what the server accepts")
    func listClamping() {
        let url = DispatcharrVODRequest.listURL(baseURL: base, kind: .movies, page: 0, pageSize: 5000)
        #expect(query(url)["page"] == "1")
        #expect(query(url)["page_size"] == "100")
    }

    @Test("Categories are requested per kind")
    func categories() {
        #expect(DispatcharrVODRequest.categoriesURL(baseURL: base, kind: .movies)?.absoluteString
                == "\(base)/api/vod/categories/?category_type=movie")
        #expect(DispatcharrVODRequest.categoriesURL(baseURL: base, kind: .series)?.absoluteString
                == "\(base)/api/vod/categories/?category_type=series")
    }

    @Test("Detail URLs use provider-info, with episodes for a series")
    func details() {
        #expect(DispatcharrVODRequest.movieDetailURL(baseURL: base, id: 42)?.absoluteString
                == "\(base)/api/vod/movies/42/provider-info/")
        #expect(DispatcharrVODRequest.seriesDetailURL(baseURL: base, id: 7)?.absoluteString
                == "\(base)/api/vod/series/7/provider-info/?include_episodes=true")
    }

    @Test("Streams go through the VOD proxy by uuid")
    func streams() {
        #expect(DispatcharrVODRequest.movieStreamURL(baseURL: base, uuid: "abc-123")?.absoluteString
                == "\(base)/proxy/vod/movie/abc-123")
        #expect(DispatcharrVODRequest.episodeStreamURL(baseURL: base, uuid: "def-456")?.absoluteString
                == "\(base)/proxy/vod/episode/def-456")
    }

    @Test("A title without a uuid has no stream URL")
    func streamNeedsUUID() {
        #expect(DispatcharrVODRequest.movieStreamURL(baseURL: base, uuid: "") == nil)
        #expect(DispatcharrVODRequest.episodeStreamURL(baseURL: base, uuid: "") == nil)
    }
}
