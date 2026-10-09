//
//  VODMovieDetail.swift
//  DispatcherPVR
//
//  /api/vod/movies/{id}/provider-info/ (#17)
//

import Foundation

nonisolated struct VODMovieDetail: Decodable, Sendable {
    let id: Int
    let uuid: String
    let name: String
    let plot: String?
    let year: Int?
    let genre: String?
    let director: String?
    let actors: String?
    let country: String?
    let rating: String?
    let durationSecs: Int?
    let cover: String?
    let backdrops: [String]

    enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, plot, year, genre, director, actors, country, rating, cover
        case durationSecs = "duration_secs"
        case coverBig = "cover_big"
        case movieImage = "movie_image"
        case backdropPath = "backdrop_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        uuid = container.vodString(forKey: .uuid) ?? ""
        name = container.vodString(forKey: .name) ?? ""
        plot = container.vodString(forKey: .plot) ?? container.vodString(forKey: .description)
        year = container.vodInt(forKey: .year).flatMap { $0 > 0 ? $0 : nil }
        genre = container.vodString(forKey: .genre)
        director = container.vodString(forKey: .director)
        actors = container.vodString(forKey: .actors)
        country = container.vodString(forKey: .country)
        rating = container.vodString(forKey: .rating)
        durationSecs = container.vodInt(forKey: .durationSecs).flatMap { $0 > 0 ? $0 : nil }
        cover = container.vodString(forKey: .coverBig)
            ?? container.vodString(forKey: .cover)
            ?? container.vodString(forKey: .movieImage)
        // A single backdrop may arrive as a bare string.
        if let list = try? container.decodeIfPresent([String].self, forKey: .backdropPath) {
            backdrops = list.filter { !$0.isEmpty }
        } else {
            backdrops = container.vodString(forKey: .backdropPath).map { [$0] } ?? []
        }
    }

    init(
        id: Int,
        uuid: String,
        name: String,
        plot: String? = nil,
        year: Int? = nil,
        genre: String? = nil,
        director: String? = nil,
        actors: String? = nil,
        country: String? = nil,
        rating: String? = nil,
        durationSecs: Int? = nil,
        cover: String? = nil,
        backdrops: [String] = []
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.plot = plot
        self.year = year
        self.genre = genre
        self.director = director
        self.actors = actors
        self.country = country
        self.rating = rating
        self.durationSecs = durationSecs
        self.cover = cover
        self.backdrops = backdrops
    }
}
