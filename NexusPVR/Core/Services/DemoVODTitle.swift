//
//  DemoVODTitle.swift
//  PVR Client
//
//  One movie or series of the demo On Demand library (#17)
//

import Foundation

nonisolated struct DemoVODTitle: Sendable {
    let id: Int
    let kind: VODKind
    let name: String
    let year: Int
    let rating: String
    let genre: String
    let category: String
    /// Runtime of a movie, or of a typical episode.
    let minutes: Int
    let plot: String
    var director: String = ""
    var actors: String = ""
    /// Bundle file names; a missing file just shows the placeholder.
    let poster: String
    let backdrop: String
    /// Series only: one array per season, each episode a (title, description).
    var seasons: [[(title: String, plot: String)]] = []

    var uuid: String { "demo-\(kind.categoryType)-\(id)" }

    func episodeUUID(season: Int, episode: Int) -> String {
        "demo-episode-\(id)-s\(season)e\(episode)"
    }
}
