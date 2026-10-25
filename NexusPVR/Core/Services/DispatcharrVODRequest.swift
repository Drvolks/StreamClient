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

    /// Every source of a title (`VODStream`).
    static func streamsURL(baseURL: String, kind: VODKind, id: Int) -> URL? {
        URL(string: "\(baseURL)/api/vod/\(kind.apiPath)/\(id)/providers/")
    }

    /// The proxy answers with a redirect to a per-session URL, which the
    /// player follows on its own. `stream` picks the source; nil leaves the
    /// choice to the server (its account priority).
    static func movieStreamURL(baseURL: String, uuid: String, stream: VODStream? = nil) -> URL? {
        guard !uuid.isEmpty else { return nil }
        return proxyURL("\(baseURL)/proxy/vod/movie/\(uuid)", stream: stream)
    }

    static func episodeStreamURL(baseURL: String, uuid: String, stream: VODStream? = nil) -> URL? {
        guard !uuid.isEmpty else { return nil }
        return proxyURL("\(baseURL)/proxy/vod/episode/\(uuid)", stream: stream)
    }

    /// Where the proxy's answer to a bare VOD URL sends the player: the
    /// session URL from a redirect, nil for anything else.
    static func sessionLocation(status: Int, location: String?) -> String? {
        guard (300...399).contains(status),
              let location = location?.trimmingCharacters(in: .whitespaces),
              !location.isEmpty else { return nil }
        return location
    }

    private static func proxyURL(_ string: String, stream: VODStream?) -> URL? {
        guard let stream else { return URL(string: string) }
        guard var components = URLComponents(string: string) else { return nil }
        components.queryItems = stream.queryItems
        return components.url
    }
}
