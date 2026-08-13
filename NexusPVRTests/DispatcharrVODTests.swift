//
//  DispatcharrVODTests.swift
//  NexusPVRTests
//
//  Tests for the Dispatcharr VOD models (#17). All fixtures use
//  synthetic UUIDs (nil-UUID with variant nibble set, e.g.
//  "00000000-0000-0000-0000-000000000001") and synthetic names so
//  the public test file carries no real user data.
//
//  Wire-format coverage: every Codable struct is decoded from a
//  realistic Dispatcharr JSON payload, the snake_case keys are
//  pinned, and round-trip through JSONEncoder confirms no field
//  loss.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct DispatcharrVODTests {

    // MARK: - VODLogo

    @Test("VODLogo decodes the snake_case cache_url")
    func vodLogoDecode() throws {
        let json = #"{"id": 7, "url": "https://example.invalid/logo.png", "cache_url": "/api/vod/vodlogos/7/cache/"}"#
        let logo = try JSONDecoder().decode(VODLogo.self, from: Data(json.utf8))
        #expect(logo.id == 7)
        #expect(logo.url == "https://example.invalid/logo.png")
        #expect(logo.cacheURL == "/api/vod/vodlogos/7/cache/")
    }

    @Test("VODLogo round-trips via Codable")
    func vodLogoRoundTrip() throws {
        let original = VODLogo(id: 1, url: "u", cacheURL: "c")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VODLogo.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - VODCategory

    @Test("VODCategory decodes the snake_case category_type")
    func vodCategoryDecode() throws {
        let json = #"{"id": 3, "name": "Drama", "category_type": "movie"}"#
        let cat = try JSONDecoder().decode(VODCategory.self, from: Data(json.utf8))
        #expect(cat.id == 3)
        #expect(cat.name == "Drama")
        #expect(cat.categoryType == "movie")
    }

    @Test("VODCategory round-trips via Codable")
    func vodCategoryRoundTrip() throws {
        let original = VODCategory(id: 3, name: "Drama", categoryType: "movie")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VODCategory.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - VODItem (browse)

    @Test("VODItem decodes the unified /all/ shape")
    func vodItemDecode() throws {
        let json = #"""
        {
          "id": 42,
          "uuid": "00000000-0000-0000-0000-000000000001",
          "name": "Example Series",
          "description": "A test fixture.",
          "year": 2024,
          "rating": "TV-14",
          "genre": "Drama",
          "duration": null,
          "content_type": "series",
          "logo": { "id": 7, "url": "https://example.invalid/l.png", "cache_url": "/api/vod/vodlogos/7/cache/" }
        }
        """#
        let item = try JSONDecoder().decode(VODItem.self, from: Data(json.utf8))
        #expect(item.id == 42)
        #expect(item.uuid == "00000000-0000-0000-0000-000000000001")
        #expect(item.name == "Example Series")
        #expect(item.contentType == "series")
        #expect(item.duration == nil, "duration is nil for series per the spec")
        #expect(item.logo?.id == 7)
    }

    @Test("VODItem tolerates missing optional fields")
    func vodItemOptionalFields() throws {
        // Bare-minimum VODItem: just id, uuid, name, content_type.
        let json = #"{"id": 1, "uuid": "00000000-0000-0000-0000-000000000002", "name": "Bare Item", "content_type": "movie"}"#
        let item = try JSONDecoder().decode(VODItem.self, from: Data(json.utf8))
        #expect(item.description == nil)
        #expect(item.year == nil)
        #expect(item.rating == nil)
        #expect(item.genre == nil)
        #expect(item.duration == nil)
        #expect(item.logo == nil)
    }

    @Test("VODItem snake_case wire format pin")
    func vodItemWireFormatPin() throws {
        // Issue #17 contract: server emits snake_case content_type
        // and snake_case everywhere. Pin the wire format explicitly
        // so a future rename is caught at PR-review time.
        let json = #"{"id": 1, "uuid": "00000000-0000-0000-0000-000000000003", "name": "X", "content_type": "movie"}"#
        let decoded = try JSONDecoder().decode(VODItem.self, from: Data(json.utf8))
        #expect(decoded.contentType == "movie")

        let encoded = String(data: try JSONEncoder().encode(decoded), encoding: .utf8)!
        #expect(encoded.contains("\"content_type\""))
        #expect(!encoded.contains("\"contentType\""), "must encode snake_case to match server")
    }

    // MARK: - VODPage

    @Test("VODPage decodes the paginated response shape")
    func vodPageDecode() throws {
        let json = #"""
        {
          "count": 200,
          "next": true,
          "previous": false,
          "results": [
            {"id": 1, "uuid": "00000000-0000-0000-0000-000000000010", "name": "Item 1", "content_type": "movie"},
            {"id": 2, "uuid": "00000000-0000-0000-0000-000000000011", "name": "Item 2", "content_type": "series"}
          ]
        }
        """#
        let page = try JSONDecoder().decode(VODPage.self, from: Data(json.utf8))
        #expect(page.count == 200)
        #expect(page.next == true)
        #expect(page.previous == false)
        #expect(page.results.count == 2)
        #expect(page.results[0].name == "Item 1")
        #expect(page.results[1].contentType == "series")
    }

    @Test("VODPage decodes an empty result set")
    func vodPageEmpty() throws {
        let json = #"{"count": 0, "next": false, "previous": false, "results": []}"#
        let page = try JSONDecoder().decode(VODPage.self, from: Data(json.utf8))
        #expect(page.results.isEmpty)
        #expect(page.next == false)
    }

    // MARK: - VODMovieDetail

    @Test("VODMovieDetail decodes the canonical provider-info payload")
    func vodMovieDetailDecode() throws {
        let json = #"""
        {
          "id": 99,
          "uuid": "00000000-0000-0000-0000-000000000099",
          "stream_id": "12345",
          "name": "Example Movie",
          "description": "A test fixture movie.",
          "plot": "Full plot text.",
          "year": 2023,
          "genre": "Action",
          "director": "Director Name",
          "actors": "Actor One, Actor Two",
          "country": "US",
          "rating": "PG-13",
          "tmdb_id": "550000",
          "imdb_id": "tt550000",
          "youtube_trailer": "https://example.invalid/trailer",
          "duration_secs": 7320,
          "backdrop_path": ["https://example.invalid/back1.jpg", "https://example.invalid/back2.jpg"],
          "cover_big": "https://example.invalid/cover.jpg",
          "container_extension": "mp4"
        }
        """#
        let movie = try JSONDecoder().decode(VODMovieDetail.self, from: Data(json.utf8))
        #expect(movie.id == 99)
        #expect(movie.streamId == "12345")
        #expect(movie.name == "Example Movie")
        #expect(movie.year == 2023)
        #expect(movie.tmdbId == "550000")
        #expect(movie.imdbId == "tt550000")
        #expect(movie.durationSecs == 7320)
        #expect(movie.backdropPath?.count == 2)
        #expect(movie.containerExtension == "mp4")
    }

    @Test("VODMovieDetail tolerates missing optional fields")
    func vodMovieDetailOptionalFields() throws {
        // Minimal payload — only required fields populated.
        let json = #"""
        {
          "id": 99,
          "uuid": "00000000-0000-0000-0000-000000000099",
          "stream_id": "12345",
          "name": "Minimal Movie"
        }
        """#
        let movie = try JSONDecoder().decode(VODMovieDetail.self, from: Data(json.utf8))
        #expect(movie.plot == nil)
        #expect(movie.director == nil)
        #expect(movie.tmdbId == nil)
        #expect(movie.backdropPath == nil)
    }

    // MARK: - VODEpisode

    @Test("VODEpisode decodes the per-episode shape")
    func vodEpisodeDecode() throws {
        let json = #"""
        {
          "id": 10,
          "uuid": "00000000-0000-0000-0000-0000000000aa",
          "name": "Pilot",
          "episode_number": 1,
          "season_number": 1,
          "description": "First episode.",
          "air_date": "2024-01-15",
          "duration_secs": 2700,
          "container_extension": "mkv"
        }
        """#
        let ep = try JSONDecoder().decode(VODEpisode.self, from: Data(json.utf8))
        #expect(ep.id == 10)
        #expect(ep.name == "Pilot")
        #expect(ep.episodeNumber == 1)
        #expect(ep.seasonNumber == 1)
        #expect(ep.airDate == "2024-01-15")
        #expect(ep.durationSecs == 2700)
        #expect(ep.containerExtension == "mkv")
    }

    // MARK: - VODSeriesDetail

    @Test("VODSeriesDetail decodes episodes keyed by season-string")
    func vodSeriesDetailDecode() throws {
        // Dispatcharr emits episodes as { "1": [...], "2": [...] } —
        // string keys, not int. Make sure the model respects that
        // and the view layer can still extract season numbers.
        let json = #"""
        {
          "id": 7,
          "name": "Example Series",
          "description": "A test fixture series.",
          "year": 2024,
          "genre": "Sci-Fi",
          "rating": "TV-MA",
          "tmdb_id": "999000",
          "imdb_id": "tt999000",
          "cover": { "id": 12, "url": "https://example.invalid/c.jpg", "cache_url": "/api/vod/vodlogos/12/cache/" },
          "episodes": {
            "1": [
              { "id": 100, "uuid": "00000000-0000-0000-0000-0000000000c8", "name": "S1E1", "episode_number": 1, "season_number": 1, "duration_secs": 2700 },
              { "id": 101, "uuid": "00000000-0000-0000-0000-0000000000c9", "name": "S1E2", "episode_number": 2, "season_number": 1, "duration_secs": 2800 }
            ],
            "2": [
              { "id": 200, "uuid": "00000000-0000-0000-0000-0000000000d0", "name": "S2E1", "episode_number": 1, "season_number": 2, "duration_secs": 2700 }
            ]
          }
        }
        """#
        let series = try JSONDecoder().decode(VODSeriesDetail.self, from: Data(json.utf8))
        #expect(series.id == 7)
        #expect(series.name == "Example Series")
        #expect(series.tmdbId == "999000")
        #expect(series.episodes.count == 2)
        #expect(series.episodes["1"]?.count == 2)
        #expect(series.episodes["1"]?[0].name == "S1E1")
        #expect(series.episodes["2"]?.count == 1)
        // Confirm the view layer can derive Int season numbers.
        let seasonNumbers = series.episodes.keys.compactMap(Int.init)
        #expect(seasonNumbers.contains(1))
        #expect(seasonNumbers.contains(2))
    }

    @Test("VODSeriesDetail tolerates an empty episodes dictionary")
    func vodSeriesDetailEmptyEpisodes() throws {
        // Forward-compat: a series with no episodes yet (mid-release,
        // or unindexed) should still decode cleanly.
        let json = #"""
        { "id": 7, "name": "Empty Series", "episodes": {} }
        """#
        let series = try JSONDecoder().decode(VODSeriesDetail.self, from: Data(json.utf8))
        #expect(series.episodes.isEmpty)
        #expect(series.name == "Empty Series")
    }

    // MARK: - VODProvider

    @Test("VODProvider decodes and flattens nested m3u_account")
    func vodProviderDecode() throws {
        // Dispatcharr emits m3u_account as a nested {id, name} dict.
        // The model flattens it for caller convenience.
        let json = #"""
        {
          "stream_id": "s-12345",
          "container_extension": "mp4",
          "quality": "1080p",
          "resolution": "1920x1080",
          "m3u_account": { "id": 7, "name": "Primary M3U" }
        }
        """#
        let p = try JSONDecoder().decode(VODProvider.self, from: Data(json.utf8))
        #expect(p.streamId == "s-12345")
        #expect(p.containerExtension == "mp4")
        #expect(p.quality == "1080p")
        #expect(p.resolution == "1920x1080")
        #expect(p.m3uAccountId == 7)
        #expect(p.m3uAccountName == "Primary M3U")
    }

    @Test("VODProvider tolerates missing m3u_account")
    func vodProviderNoAccount() throws {
        // The m3u_account sub-object can be missing (rare, but the
        // server may emit it for orphan providers). Model should
        // decode with m3uAccountId / m3uAccountName nil.
        let json = #"""
        { "stream_id": "s-99999", "container_extension": "ts" }
        """#
        let p = try JSONDecoder().decode(VODProvider.self, from: Data(json.utf8))
        #expect(p.streamId == "s-99999")
        #expect(p.containerExtension == "ts")
        #expect(p.m3uAccountId == nil)
        #expect(p.m3uAccountName == nil)
    }

    @Test("VODProvider round-trips with the nested m3u_account")
    func vodProviderRoundTrip() throws {
        let original = VODProvider(streamId: "s-1", containerExtension: "mkv", quality: "4K", resolution: "3840x2160", m3uAccountId: 5, m3uAccountName: "Backup")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VODProvider.self, from: data)
        #expect(decoded.streamId == original.streamId)
        #expect(decoded.m3uAccountId == original.m3uAccountId)
        #expect(decoded.m3uAccountName == original.m3uAccountName)
    }
}