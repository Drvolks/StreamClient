//
//  VODSeriesDetail.swift
//  DispatcherPVR
//
//  /api/vod/series/{id}/provider-info/?include_episodes=true (#17)
//

import Foundation

nonisolated struct VODSeriesDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let year: Int?
    let genre: String?
    let rating: String?
    let cover: VODLogo?
    let backdrops: [String]
    /// Ordered by season number, specials (season 0) last.
    let seasons: [VODSeason]

    enum CodingKeys: String, CodingKey {
        case id, name, description, year, genre, rating, cover, episodes
        case backdropPath = "backdrop_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.vodString(forKey: .name) ?? ""
        description = container.vodString(forKey: .description)
        year = container.vodInt(forKey: .year).flatMap { $0 > 0 ? $0 : nil }
        genre = container.vodString(forKey: .genre)
        rating = container.vodString(forKey: .rating)
        cover = try? container.decodeIfPresent(VODLogo.self, forKey: .cover)
        if let list = try? container.decodeIfPresent([String].self, forKey: .backdropPath) {
            backdrops = list.filter { !$0.isEmpty }
        } else {
            backdrops = container.vodString(forKey: .backdropPath).map { [$0] } ?? []
        }
        // Keyed by season number; an unfetched series sends {} or nothing.
        let bySeason = (try? container.decodeIfPresent([String: [VODEpisode]].self, forKey: .episodes)) ?? [:]
        seasons = Self.seasons(from: bySeason.values.flatMap { $0 })
    }

    init(
        id: Int,
        name: String,
        description: String? = nil,
        year: Int? = nil,
        genre: String? = nil,
        rating: String? = nil,
        cover: VODLogo? = nil,
        backdrops: [String] = [],
        episodes: [VODEpisode] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.year = year
        self.genre = genre
        self.rating = rating
        self.cover = cover
        self.backdrops = backdrops
        self.seasons = Self.seasons(from: episodes)
    }

    var episodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.count } }

    /// Every episode in watch order.
    var allEpisodes: [VODEpisode] { seasons.flatMap(\.episodes) }

    /// Groups by the episode's own season number rather than the response
    /// key, then orders seasons 1…n with specials last.
    static func seasons(from episodes: [VODEpisode]) -> [VODSeason] {
        Dictionary(grouping: episodes) { max($0.seasonNumber ?? 0, 0) }
            .map { number, episodes in
                VODSeason(
                    number: number,
                    episodes: episodes.sorted {
                        ($0.episodeNumber ?? .max, $0.id) < ($1.episodeNumber ?? .max, $1.id)
                    }
                )
            }
            .sorted { lhs, rhs in
                if (lhs.number == 0) != (rhs.number == 0) { return rhs.number == 0 }
                return lhs.number < rhs.number
            }
    }
}
