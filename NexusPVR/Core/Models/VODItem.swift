//
//  VODItem.swift
//  DispatcherPVR
//
//  A movie or series as listed by /api/vod/movies/ and /api/vod/series/ (#17)
//

import Foundation

nonisolated struct VODItem: Decodable, Identifiable, Hashable, Sendable {
    /// Movie and series ids overlap, so identity includes the kind.
    var id: String { "\(kind.categoryType)-\(itemId)" }

    let itemId: Int
    let uuid: String
    let name: String
    let description: String?
    let year: Int?
    let rating: String?
    let genre: String?
    /// Movies only.
    let durationSecs: Int?
    /// Series only, when the server has counted them.
    let episodeCount: Int?
    let logo: VODLogo?
    /// The list endpoints don't say which they are; the client stamps it.
    var kind: VODKind

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, year, rating, genre, logo
        case durationSecs = "duration_secs"
        case episodeCount = "episode_count"
        case contentType = "content_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(Int.self, forKey: .id)
        uuid = container.vodString(forKey: .uuid) ?? ""
        name = container.vodString(forKey: .name) ?? ""
        description = container.vodString(forKey: .description)
        year = container.vodInt(forKey: .year).flatMap { $0 > 0 ? $0 : nil }
        rating = container.vodString(forKey: .rating)
        genre = container.vodString(forKey: .genre)
        durationSecs = container.vodInt(forKey: .durationSecs).flatMap { $0 > 0 ? $0 : nil }
        episodeCount = container.vodInt(forKey: .episodeCount)
        logo = try? container.decodeIfPresent(VODLogo.self, forKey: .logo)
        kind = container.vodString(forKey: .contentType) == VODKind.series.categoryType ? .series : .movies
    }

    init(
        itemId: Int,
        uuid: String,
        name: String,
        kind: VODKind,
        description: String? = nil,
        year: Int? = nil,
        rating: String? = nil,
        genre: String? = nil,
        durationSecs: Int? = nil,
        episodeCount: Int? = nil,
        logo: VODLogo? = nil
    ) {
        self.itemId = itemId
        self.uuid = uuid
        self.name = name
        self.kind = kind
        self.description = description
        self.year = year
        self.rating = rating
        self.genre = genre
        self.durationSecs = durationSecs
        self.episodeCount = episodeCount
        self.logo = logo
    }

    func stamped(_ kind: VODKind) -> VODItem {
        var copy = self
        copy.kind = kind
        return copy
    }

    /// "2019 · 1h 42m · Comedy" under a poster.
    var metaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let durationSecs { parts.append(formatDuration(durationSecs)) }
        if let episodeCount, episodeCount > 0 {
            parts.append("\(episodeCount) episode\(episodeCount == 1 ? "" : "s")")
        }
        if let genre = genre?.split(separator: ",").first.map({ $0.trimmingCharacters(in: .whitespaces) }),
           !genre.isEmpty {
            parts.append(genre)
        }
        return parts.joined(separator: " · ")
    }
}
