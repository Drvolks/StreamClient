//
//  VODPlayable.swift
//  DispatcherPVR
//
//  What the On Demand pages hand to the player: a movie or one episode (#17)
//

import Foundation

nonisolated struct VODPlayable: Identifiable, Equatable, Sendable {
    /// The movie's or the episode's uuid; also keys its saved position.
    let uuid: String
    /// Shown in the player, e.g. "Breaking Bread · S01E02 · Crust in the Bag".
    let title: String
    let isEpisode: Bool

    var id: String { uuid }

    static func movie(uuid: String, name: String) -> VODPlayable {
        VODPlayable(uuid: uuid, title: name, isEpisode: false)
    }

    static func episode(_ episode: VODEpisode, seriesName: String) -> VODPlayable {
        let parts = [seriesName, episode.code, episode.displayName].compactMap { $0 }.filter { !$0.isEmpty }
        return VODPlayable(uuid: episode.uuid, title: parts.joined(separator: " · "), isEpisode: true)
    }
}
