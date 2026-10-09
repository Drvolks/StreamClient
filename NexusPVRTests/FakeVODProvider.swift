//
//  FakeVODProvider.swift
//  NexusPVRTests
//
//  An in-memory VOD backend for view model tests: serves a fixed library a
//  page at a time and records what it was asked.
//

import Foundation
@testable import NextPVR

@MainActor
final class FakeVODProvider: VODProviding {
    var library: [VODItem] = []
    var categories: [VODCategory] = []
    var movieDetails: [Int: VODMovieDetail] = [:]
    var seriesDetails: [Int: VODSeriesDetail] = [:]
    /// Thrown by the next list or detail request, then cleared.
    var nextError: Error?
    /// Every list request, in order.
    private(set) var listRequests: [(kind: VODKind, page: Int, search: String?, category: String?)] = []

    static func movies(_ count: Int) -> [VODItem] {
        (1...max(count, 1)).prefix(count).map {
            VODItem(itemId: $0, uuid: "movie-\($0)", name: String(format: "Movie %03d", $0), kind: .movies)
        }
    }

    private func throwIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func getVODCounts() async throws -> VODCounts {
        VODCounts(
            movies: library.filter { $0.kind == .movies }.count,
            series: library.filter { $0.kind == .series }.count
        )
    }

    func getVODCategories(kind: VODKind) async throws -> [VODCategory] {
        categories.filter { $0.categoryType == kind.categoryType }
    }

    func getVODItems(kind: VODKind, page: Int, pageSize: Int, search: String?, category: String?) async throws -> VODPage {
        listRequests.append((kind, page, search, category))
        try throwIfNeeded()
        var matches = library.filter { $0.kind == kind }
        if let search { matches = matches.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        if let category { matches = matches.filter { $0.genre == category } }
        let start = (page - 1) * pageSize
        let slice = Array(matches.dropFirst(start).prefix(pageSize))
        return VODPage(items: slice, totalCount: matches.count, hasMore: start + slice.count < matches.count)
    }

    func getVODMovieDetail(id: Int) async throws -> VODMovieDetail {
        try throwIfNeeded()
        guard let detail = movieDetails[id] else { throw PVRClientError.invalidResponse }
        return detail
    }

    func getVODSeriesDetail(id: Int) async throws -> VODSeriesDetail {
        try throwIfNeeded()
        guard let detail = seriesDetails[id] else { throw PVRClientError.invalidResponse }
        return detail
    }

    func vodMovieStreamURL(uuid: String) throws -> URL {
        URL(string: "http://fake.local/proxy/vod/movie/\(uuid)")!
    }

    func vodEpisodeStreamURL(uuid: String) throws -> URL {
        URL(string: "http://fake.local/proxy/vod/episode/\(uuid)")!
    }

    func vodImageURL(_ reference: String?) -> URL? {
        reference.flatMap { URL(string: $0) }
    }
}
