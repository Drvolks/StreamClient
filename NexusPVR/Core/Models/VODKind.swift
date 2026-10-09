//
//  VODKind.swift
//  DispatcherPVR
//
//  The two halves of the Dispatcharr on-demand library (#17)
//

import Foundation

nonisolated enum VODKind: String, CaseIterable, Identifiable, Sendable {
    case movies = "Movies"
    case series = "Series"

    var id: String { rawValue }

    var title: String { rawValue }

    /// Path component under `/api/vod/`.
    var apiPath: String {
        switch self {
        case .movies: "movies"
        case .series: "series"
        }
    }

    /// `category_type` value, also the suffix of a `Name|type` category filter.
    var categoryType: String {
        switch self {
        case .movies: "movie"
        case .series: "series"
        }
    }

    /// "1 movie", "12 series".
    func countLabel(_ count: Int) -> String {
        switch self {
        case .movies: "\(count) movie\(count == 1 ? "" : "s")"
        case .series: "\(count) series"
        }
    }
}
