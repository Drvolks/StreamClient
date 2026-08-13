//
//  DispatcharrVOD.swift
//  nextpvr-apple-client
//
//  VOD (video on demand) models for Dispatcharr (#17).
//
//  All five structs are derived from the API contract in the pinned
//  comment on issue #17, which itself is derived from reading the
//  current Dispatcharr source (`apps/vod/`). Wire format is
//  snake_case; we map to Swift camelCase via explicit CodingKeys.
//
//  All fields are optional where the server can legitimately omit
//  them, so the model survives a Dispatcharr upgrade that adds a
//  new field without a corresponding model bump on our side.
//
//  Scope of this file: models only. The `DispatcherClient`
//  extensions and view skeletons land in follow-up PRs — see the
//  PR body for the breakdown.
//

import Foundation

// MARK: - VODLogo

nonisolated struct VODLogo: Codable, Equatable, Sendable {
    let id: Int
    let url: String
    let cacheURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case cacheURL = "cache_url"
    }
}

// MARK: - VODCategory

nonisolated struct VODCategory: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    /// "movie" | "series" (Dispatcharr's two category_type values)
    let categoryType: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case categoryType = "category_type"
    }
}

// MARK: - VODItem (browse shape)

nonisolated struct VODItem: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let uuid: String
    let name: String
    let description: String?
    let year: Int?
    let rating: String?
    let genre: String?
    /// Seconds; nil for series (where total runtime is per-episode)
    let duration: Int?
    /// "movie" | "series"
    let contentType: String
    let logo: VODLogo?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case description
        case year
        case rating
        case genre
        case duration
        case contentType = "content_type"
        case logo
    }
}

// MARK: - VODPage (paginated browse response)

nonisolated struct VODPage: Codable, Equatable, Sendable {
    let count: Int
    let next: Bool
    let previous: Bool
    let results: [VODItem]
}

// MARK: - VODMovieDetail

nonisolated struct VODMovieDetail: Codable, Equatable, Sendable {
    let id: Int
    let uuid: String
    /// Stream ID — used as `?stream_id=` to pick a specific provider
    /// in the multi-provider case (issue #17 spec §"Streaming").
    let streamId: String
    let name: String
    let description: String?
    let plot: String?
    let year: Int?
    let genre: String?
    let director: String?
    let actors: String?
    let country: String?
    let rating: String?
    let tmdbId: String?
    let imdbId: String?
    let youtubeTrailer: String?
    let durationSecs: Int?
    let backdropPath: [String]?
    let coverBig: String?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case streamId = "stream_id"
        case name
        case description
        case plot
        case year
        case genre
        case director
        case actors
        case country
        case rating
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case youtubeTrailer = "youtube_trailer"
        case durationSecs = "duration_secs"
        case backdropPath = "backdrop_path"
        case coverBig = "cover_big"
        case containerExtension = "container_extension"
    }
}

// MARK: - VODEpisode

nonisolated struct VODEpisode: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let uuid: String
    let name: String
    let episodeNumber: Int?
    let seasonNumber: Int?
    let description: String?
    /// ISO date string "YYYY-MM-DD"; not parsed to `Date` because
    /// the server emits it in mixed shapes (sometimes "2008-01-20",
    /// sometimes a full timestamp) and the UI only needs the string.
    let airDate: String?
    let durationSecs: Int?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case description
        case airDate = "air_date"
        case durationSecs = "duration_secs"
        case containerExtension = "container_extension"
    }
}

// MARK: - VODSeriesDetail

nonisolated struct VODSeriesDetail: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let year: Int?
    let genre: String?
    let rating: String?
    let tmdbId: String?
    let imdbId: String?
    let cover: VODLogo?
    /// Episodes keyed by season number as a string ("1", "2", ...)
    /// because that's how Dispatcharr emits the dictionary and JSON
    /// keys are always strings. The view layer converts to Int for
    /// display and ordering.
    let episodes: [String: [VODEpisode]]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case year
        case genre
        case rating
        case tmdbId = "tmdb_id"
        case imdbId = "imdb_id"
        case cover
        case episodes
    }
}

// MARK: - VODProviders (multi-provider movie response)

nonisolated struct VODProvider: Codable, Identifiable, Equatable, Sendable {
    let streamId: String
    let containerExtension: String?
    let quality: String?
    let resolution: String?
    let m3uAccountId: Int?
    let m3uAccountName: String?

    var id: String { streamId }

    /// Explicit memberwise initializer so the model can be
    /// constructed directly in tests (the custom `init(from:)`
    /// below would otherwise hide the synthesized memberwise form).
    init(streamId: String, containerExtension: String? = nil, quality: String? = nil, resolution: String? = nil, m3uAccountId: Int? = nil, m3uAccountName: String? = nil) {
        self.streamId = streamId
        self.containerExtension = containerExtension
        self.quality = quality
        self.resolution = resolution
        self.m3uAccountId = m3uAccountId
        self.m3uAccountName = m3uAccountName
    }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case containerExtension = "container_extension"
        case quality
        case resolution
        case m3uAccountId = "m3u_account"
        case m3uAccountName = "m3u_account_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamId = try c.decode(String.self, forKey: .streamId)
        containerExtension = try c.decodeIfPresent(String.self, forKey: .containerExtension)
        quality = try c.decodeIfPresent(String.self, forKey: .quality)
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution)
        // `m3u_account` is a nested {id, name} dict on the server;
        // flatten it for caller convenience.
        if let account = try? c.nestedContainer(keyedBy: M3UAccountKeys.self, forKey: .m3uAccountId) {
            m3uAccountId = try account.decodeIfPresent(Int.self, forKey: .id)
            m3uAccountName = try account.decodeIfPresent(String.self, forKey: .name)
        } else {
            m3uAccountId = nil
            m3uAccountName = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(streamId, forKey: .streamId)
        try c.encodeIfPresent(containerExtension, forKey: .containerExtension)
        try c.encodeIfPresent(quality, forKey: .quality)
        try c.encodeIfPresent(resolution, forKey: .resolution)
        // Round-trip the nested m3u_account dict.
        if m3uAccountId != nil || m3uAccountName != nil {
            var account = c.nestedContainer(keyedBy: M3UAccountKeys.self, forKey: .m3uAccountId)
            try account.encodeIfPresent(m3uAccountId, forKey: .id)
            try account.encodeIfPresent(m3uAccountName, forKey: .name)
        }
    }

    private enum M3UAccountKeys: String, CodingKey {
        case id
        case name
    }
}