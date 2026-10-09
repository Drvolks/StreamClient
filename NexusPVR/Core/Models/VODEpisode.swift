//
//  VODEpisode.swift
//  DispatcherPVR
//
//  One episode of a VOD series (#17)
//

import Foundation

nonisolated struct VODEpisode: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let uuid: String
    let name: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let description: String?
    /// "2008-01-20"
    let airDate: String?
    let durationSecs: Int?

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, title, description, plot
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case durationSecs = "duration_secs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        uuid = container.vodString(forKey: .uuid) ?? ""
        name = container.vodString(forKey: .name) ?? container.vodString(forKey: .title) ?? ""
        seasonNumber = container.vodInt(forKey: .seasonNumber)
        episodeNumber = container.vodInt(forKey: .episodeNumber)
        description = container.vodString(forKey: .description) ?? container.vodString(forKey: .plot)
        airDate = container.vodString(forKey: .airDate)
        durationSecs = container.vodInt(forKey: .durationSecs).flatMap { $0 > 0 ? $0 : nil }
    }

    init(
        id: Int,
        uuid: String,
        name: String,
        seasonNumber: Int?,
        episodeNumber: Int?,
        description: String? = nil,
        airDate: String? = nil,
        durationSecs: Int? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.description = description
        self.airDate = airDate
        self.durationSecs = durationSecs
    }

    private static let airDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "Jan 20, 2008 · 45 min"
    var metaLine: String {
        var parts: [String] = []
        if let date = airDate.flatMap({ Self.airDateParser.date(from: String($0.prefix(10))) }) {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let durationSecs { parts.append("\(max(durationSecs / 60, 1)) min") }
        return parts.joined(separator: " · ")
    }

    /// "S02E05", or "E05" when the season is unknown.
    var code: String? {
        guard let episodeNumber else { return nil }
        let episode = String(format: "E%02d", episodeNumber)
        guard let seasonNumber, seasonNumber > 0 else { return episode }
        return String(format: "S%02d", seasonNumber) + episode
    }

    /// Providers often name an episode "Show - S01E02 - Title"; keep the title.
    var displayName: String {
        let parts = name.components(separatedBy: " - ")
        if parts.count >= 3,
           parts[parts.count - 2].range(of: #"^S\d+E\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil,
           let last = parts.last, !last.isEmpty {
            return last
        }
        if name.isEmpty, let episodeNumber { return "Episode \(episodeNumber)" }
        return name
    }
}
