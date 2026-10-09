//
//  DispatcharrVODRequest.swift
//  DispatcherPVR
//
//  URLs of the Dispatcharr VOD API (#17). Pure, so they can be tested
//  without a client.
//

import Foundation

nonisolated enum DispatcharrVODRequest {
    /// The server caps `page_size` at 100.
    static let maxPageSize = 100

    /// `/api/vod/movies/` or `/api/vod/series/`, ordered by name.
    /// `category` is a `VODCategory.filterValue` ("Name|movie").
    static func listURL(
        baseURL: String,
        kind: VODKind,
        page: Int,
        pageSize: Int,
        search: String? = nil,
        category: String? = nil
    ) -> URL? {
        guard var components = URLComponents(string: "\(baseURL)/api/vod/\(kind.apiPath)/") else { return nil }
        var items = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "page_size", value: String(min(max(pageSize, 1), maxPageSize))),
            URLQueryItem(name: "ordering", value: "name")
        ]
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        if let category, !category.isEmpty {
            items.append(URLQueryItem(name: "category", value: category))
        }
        components.queryItems = items
        return components.url
    }

    static func categoriesURL(baseURL: String, kind: VODKind) -> URL? {
        URL(string: "\(baseURL)/api/vod/categories/?category_type=\(kind.categoryType)")
    }

    static func movieDetailURL(baseURL: String, id: Int) -> URL? {
        URL(string: "\(baseURL)/api/vod/movies/\(id)/provider-info/")
    }

    static func seriesDetailURL(baseURL: String, id: Int) -> URL? {
        URL(string: "\(baseURL)/api/vod/series/\(id)/provider-info/?include_episodes=true")
    }

    /// The proxy answers with a redirect to a per-session URL, which the
    /// player follows on its own.
    static func movieStreamURL(baseURL: String, uuid: String) -> URL? {
        guard !uuid.isEmpty else { return nil }
        return URL(string: "\(baseURL)/proxy/vod/movie/\(uuid)")
    }

    static func episodeStreamURL(baseURL: String, uuid: String) -> URL? {
        guard !uuid.isEmpty else { return nil }
        return URL(string: "\(baseURL)/proxy/vod/episode/\(uuid)")
    }
}
