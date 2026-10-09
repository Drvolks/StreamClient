//
//  VODProviding.swift
//  DispatcherPVR
//
//  What the On Demand pages need from a backend (#17). `DispatcherClient`
//  is the only implementation; the protocol keeps the view models testable.
//

import Foundation

@MainActor
protocol VODProviding: AnyObject {
    /// How many movies and series the server offers. Zero of both hides the
    /// On Demand menu.
    func getVODCounts() async throws -> VODCounts
    func getVODCategories(kind: VODKind) async throws -> [VODCategory]
    /// `category` is a `VODCategory.filterValue`.
    func getVODItems(kind: VODKind, page: Int, pageSize: Int, search: String?, category: String?) async throws -> VODPage
    func getVODMovieDetail(id: Int) async throws -> VODMovieDetail
    func getVODSeriesDetail(id: Int) async throws -> VODSeriesDetail
    func vodMovieStreamURL(uuid: String) throws -> URL
    func vodEpisodeStreamURL(uuid: String) throws -> URL
    /// Resolves an image reference from a VOD response, which may be an
    /// absolute URL or a path on the server.
    func vodImageURL(_ reference: String?) -> URL?
}
