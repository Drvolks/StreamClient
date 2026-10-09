//
//  VODModelsTests.swift
//  NexusPVRTests
//
//  Decoding of the Dispatcharr VOD responses (#17) and the values derived
//  from them: seasons, episode codes, poster meta lines.
//

import Testing
import Foundation
@testable import NextPVR

struct VODModelsTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - List items

    @Test("Decodes a movie as /api/vod/movies/ sends it")
    func decodesMovieItem() throws {
        let json = #"""
        {"id":42,"uuid":"550e8400-e29b-41d4-a716-446655440000","name":"Heat","description":"A heist.",
         "year":1995,"rating":"R","genre":"Crime, Drama","duration_secs":10200,
         "logo":{"id":7,"name":"Heat","url":"https://img.example/heat.jpg","cache_url":"/api/vod/vodlogos/7/cache/"}}
        """#
        let item = try decode(VODItem.self, json)
        #expect(item.itemId == 42)
        #expect(item.uuid == "550e8400-e29b-41d4-a716-446655440000")
        #expect(item.kind == .movies)
        #expect(item.durationSecs == 10200)
        #expect(item.logo?.preferredURLString == "/api/vod/vodlogos/7/cache/")
        #expect(item.metaLine == "1995 · 2h 50m · Crime")
    }

    @Test("A series item carries its episode count, whichever type the server uses")
    func decodesSeriesItem() throws {
        let asString = try decode(VODItem.self, #"{"id":3,"uuid":"u","name":"Show","year":2008,"episode_count":"62"}"#)
        let asNumber = try decode(VODItem.self, #"{"id":3,"uuid":"u","name":"Show","year":2008,"episode_count":62}"#)
        #expect(asString.episodeCount == 62)
        #expect(asNumber.episodeCount == 62)
        #expect(asNumber.stamped(.series).metaLine == "2008 · 62 episodes")
    }

    @Test("Missing and null fields decode as nil, and a zero year is no year")
    func decodesSparseItem() throws {
        let item = try decode(VODItem.self, #"{"id":1,"uuid":"u","name":"Bare","year":0,"logo":null,"rating":""}"#)
        #expect(item.year == nil)
        #expect(item.logo == nil)
        #expect(item.rating == nil)
        #expect(item.metaLine.isEmpty)
    }

    @Test("Movie and series with the same server id are different items")
    func identityIncludesKind() {
        let movie = VODItem(itemId: 9, uuid: "a", name: "Same", kind: .movies)
        #expect(movie.id != movie.stamped(.series).id)
    }

    @Test("content_type from the unified endpoint sets the kind")
    func contentTypeSetsKind() throws {
        let item = try decode(VODItem.self, #"{"id":1,"uuid":"u","name":"X","content_type":"series"}"#)
        #expect(item.kind == .series)
    }

    @Test("A logo without a cached copy falls back to its source URL")
    func logoFallsBackToURL() {
        #expect(VODLogo(id: nil, url: "https://a/b.jpg", cacheURL: "").preferredURLString == "https://a/b.jpg")
        #expect(VODLogo().preferredURLString == nil)
    }

    // MARK: - Movie detail

    @Test("Decodes movie provider-info, coercing loose provider values")
    func decodesMovieDetail() throws {
        let json = #"""
        {"id":42,"uuid":"abc","stream_id":"991","name":"Heat","description":"Short.","plot":"Long plot.",
         "year":"1995","genre":"Crime","director":"Michael Mann","actors":"Al Pacino","country":"",
         "rating":8.3,"duration_secs":"10200","backdrop_path":["/b1.jpg","","/b2.jpg"],
         "cover":"/c.jpg","cover_big":"/big.jpg","movie_image":"/m.jpg","container_extension":"mkv"}
        """#
        let detail = try decode(VODMovieDetail.self, json)
        #expect(detail.plot == "Long plot.")
        #expect(detail.year == 1995)
        #expect(detail.rating == "8.3")
        #expect(detail.durationSecs == 10200)
        #expect(detail.country == nil)
        #expect(detail.cover == "/big.jpg")
        #expect(detail.backdrops == ["/b1.jpg", "/b2.jpg"])
    }

    @Test("A movie without a plot uses its description, and a lone backdrop string is kept")
    func movieDetailFallbacks() throws {
        let detail = try decode(
            VODMovieDetail.self,
            #"{"id":1,"uuid":"u","name":"M","description":"Only this.","backdrop_path":"/one.jpg"}"#
        )
        #expect(detail.plot == "Only this.")
        #expect(detail.backdrops == ["/one.jpg"])
        #expect(detail.cover == nil)
    }

    // MARK: - Series detail

    private let seriesJSON = #"""
    {"id":5,"name":"Breaking Bad","description":"Chemistry.","year":2008,"genre":"Drama","rating":"TV-MA",
     "cover":{"id":null,"url":"https://p/cover.jpg","cache_url":"/api/vod/series/5/image/?k=movie_image","name":"Breaking Bad"},
     "backdrop_path":["/bb.jpg"],
     "episodes":{
       "2":[{"id":21,"uuid":"e21","name":"Seven Thirty-Seven","episode_number":1,"season_number":2,"duration_secs":2820,"air_date":"2009-03-08"}],
       "1":[{"id":12,"uuid":"e12","name":"Cat's in the Bag","episode_number":2,"season_number":1},
            {"id":11,"uuid":"e11","title":"Pilot","episode_number":1,"season_number":1,"plot":"It begins."}],
       "0":[{"id":90,"uuid":"e90","name":"Minisode","episode_number":1,"season_number":0}]
     }}
    """#

    @Test("Seasons come out in order with specials last, episodes in order within them")
    func decodesSeriesSeasons() throws {
        let detail = try decode(VODSeriesDetail.self, seriesJSON)
        #expect(detail.seasons.map(\.number) == [1, 2, 0])
        #expect(detail.seasons.map(\.title) == ["Season 1", "Season 2", "Specials"])
        #expect(detail.seasons[0].episodes.map(\.id) == [11, 12])
        #expect(detail.episodeCount == 4)
        #expect(detail.allEpisodes.map(\.uuid) == ["e11", "e12", "e21", "e90"])
        #expect(detail.cover?.id == nil)
        #expect(detail.cover?.preferredURLString == "/api/vod/series/5/image/?k=movie_image")
        #expect(detail.backdrops == ["/bb.jpg"])
    }

    @Test("Episodes fall back to title and plot when name and description are missing")
    func episodeFallbackFields() throws {
        let detail = try decode(VODSeriesDetail.self, seriesJSON)
        let pilot = try #require(detail.seasons.first?.episodes.first)
        #expect(pilot.name == "Pilot")
        #expect(pilot.description == "It begins.")
    }

    @Test("A series whose episodes were not fetched yet has no seasons")
    func seriesWithoutEpisodes() throws {
        let empty = try decode(VODSeriesDetail.self, #"{"id":5,"name":"New","episodes":{}}"#)
        let missing = try decode(VODSeriesDetail.self, #"{"id":5,"name":"New"}"#)
        #expect(empty.seasons.isEmpty)
        #expect(missing.seasons.isEmpty)
        #expect(missing.episodeCount == 0)
    }

    @Test("Episodes are grouped by their own season number, not the response key")
    func groupsBySeasonNumber() {
        let seasons = VODSeriesDetail.seasons(from: [
            VODEpisode(id: 3, uuid: "c", name: "C", seasonNumber: 10, episodeNumber: 1),
            VODEpisode(id: 2, uuid: "b", name: "B", seasonNumber: 2, episodeNumber: 2),
            VODEpisode(id: 1, uuid: "a", name: "A", seasonNumber: 2, episodeNumber: 1),
            VODEpisode(id: 4, uuid: "d", name: "D", seasonNumber: nil, episodeNumber: nil),
        ])
        #expect(seasons.map(\.number) == [2, 10, 0])
        #expect(seasons[0].episodes.map(\.uuid) == ["a", "b"])
        #expect(seasons[1].shortTitle == "S10")
    }

    // MARK: - Episodes

    @Test("Episode code pads season and episode, and drops an unknown season")
    func episodeCode() {
        #expect(VODEpisode(id: 1, uuid: "u", name: "N", seasonNumber: 2, episodeNumber: 5).code == "S02E05")
        #expect(VODEpisode(id: 1, uuid: "u", name: "N", seasonNumber: 12, episodeNumber: 104).code == "S12E104")
        #expect(VODEpisode(id: 1, uuid: "u", name: "N", seasonNumber: nil, episodeNumber: 3).code == "E03")
        #expect(VODEpisode(id: 1, uuid: "u", name: "N", seasonNumber: 1, episodeNumber: nil).code == nil)
    }

    @Test("Display name strips a provider's 'Show - S01E02 - ' prefix")
    func episodeDisplayName() {
        let prefixed = VODEpisode(id: 1, uuid: "u", name: "Breaking Bad - S01E02 - Cat's in the Bag", seasonNumber: 1, episodeNumber: 2)
        let plain = VODEpisode(id: 2, uuid: "u", name: "Half - Measures", seasonNumber: 3, episodeNumber: 12)
        let unnamed = VODEpisode(id: 3, uuid: "u", name: "", seasonNumber: 1, episodeNumber: 4)
        #expect(prefixed.displayName == "Cat's in the Bag")
        #expect(plain.displayName == "Half - Measures")
        #expect(unnamed.displayName == "Episode 4")
    }

    @Test("Episode meta line shows runtime in minutes, and survives a bad air date")
    func episodeMetaLine() {
        let dated = VODEpisode(id: 1, uuid: "u", name: "N", seasonNumber: 1, episodeNumber: 1, airDate: "2008-01-20", durationSecs: 2700)
        let undated = VODEpisode(id: 1, uuid: "u", name: "N", seasonNumber: 1, episodeNumber: 1, airDate: "soon", durationSecs: 2700)
        #expect(dated.metaLine.hasSuffix(" · 45 min"))
        #expect(dated.metaLine.contains("2008"))
        #expect(undated.metaLine == "45 min")
    }

    // MARK: - Counts, kinds, categories

    @Test("Counts report which kinds have something to browse")
    func countsAvailableKinds() {
        #expect(VODCounts.none.isEmpty)
        #expect(VODCounts.none.availableKinds.isEmpty)
        #expect(VODCounts(movies: 0, series: 4).availableKinds == [.series])
        #expect(VODCounts(movies: 2, series: 4).availableKinds == [.movies, .series])
        #expect(VODCounts(movies: 2, series: 4).count(for: .series) == 4)
    }

    @Test("Kinds map to the API's paths and category types")
    func kindAPIValues() {
        #expect(VODKind.movies.apiPath == "movies")
        #expect(VODKind.series.apiPath == "series")
        #expect(VODKind.movies.categoryType == "movie")
        #expect(VODKind.series.categoryType == "series")
        #expect(VODKind.movies.countLabel(1) == "1 movie")
        #expect(VODKind.movies.countLabel(3) == "3 movies")
        #expect(VODKind.series.countLabel(1) == "1 series")
    }

    @Test("A category filters as Name|type")
    func categoryFilterValue() throws {
        let category = try decode(VODCategory.self, #"{"id":4,"name":"Sci-Fi","category_type":"movie","m3u_accounts":[]}"#)
        #expect(category.filterValue == "Sci-Fi|movie")
    }

    // MARK: - Playables

    @Test("An episode's player title names the series, the code and the episode")
    func playableTitles() {
        let episode = VODEpisode(id: 1, uuid: "e1", name: "Pilot", seasonNumber: 1, episodeNumber: 1)
        let playable = VODPlayable.episode(episode, seriesName: "Breaking Bread")
        #expect(playable.title == "Breaking Bread · S01E01 · Pilot")
        #expect(playable.isEpisode)
        #expect(playable.uuid == "e1")
        #expect(VODPlayable.movie(uuid: "m1", name: "Heat").isEpisode == false)
    }
}
