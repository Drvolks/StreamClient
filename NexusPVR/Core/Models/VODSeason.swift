//
//  VODSeason.swift
//  DispatcherPVR
//
//  A season of a VOD series, with its episodes in order (#17)
//

import Foundation

nonisolated struct VODSeason: Identifiable, Hashable, Sendable {
    /// 0 collects specials and episodes without a season.
    let number: Int
    let episodes: [VODEpisode]

    var id: Int { number }

    var title: String { number > 0 ? "Season \(number)" : "Specials" }

    /// Short label for the season picker.
    var shortTitle: String { number > 0 ? "S\(number)" : "Specials" }
}
