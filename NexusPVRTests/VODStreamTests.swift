//
//  VODStreamTests.swift
//  NexusPVRTests
//
//  Choosing the source of an On Demand title, like Dispatcharr's "Stream
//  Selection": decoding `/providers/`, labels, the proxy query, and when the
//  detail page offers a choice.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct VODStreamTests {

    private let base = "http://tv:9191"

    private func decode(_ json: String) throws -> VODStream {
        try JSONDecoder().decode(VODStream.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    @Test("A movie source decodes with its account, stream id and quality")
    func decodesMovieSource() throws {
        let stream = try decode(#"""
        {"id":12,"m3u_account":{"id":3,"name":"Strong (remy)","server_url":"x"},"stream_id":"771230",
         "container_extension":"mkv","quality_info":{"quality":"1080p"},"movie":{"id":1}}
        """#)
        #expect(stream.id == 12)
        #expect(stream.accountId == 3)
        #expect(stream.streamId == "771230")
        #expect(stream.quality == "1080p")
        #expect(stream.label == "Strong (remy) - 1080p (Stream 771230)")
    }

    @Test("A series source has no stream id, and a numeric stream id is kept")
    func decodesOtherShapes() throws {
        let series = try decode(#"{"id":5,"m3u_account":{"id":2,"name":"Backup"},"external_series_id":"99"}"#)
        #expect(series.streamId == nil)
        #expect(series.label == "Backup")

        let numeric = try decode(#"{"id":6,"m3u_account":{"id":2,"name":"Backup"},"stream_id":42,"quality_info":null}"#)
        #expect(numeric.streamId == "42")
        #expect(numeric.quality == nil)
    }

    @Test("Quality falls back to resolution, then bitrate")
    func qualityFallback() throws {
        let stream = try decode(#"{"id":1,"m3u_account":{"id":1,"name":"A"},"quality_info":{"resolution":"1920x1080"}}"#)
        #expect(stream.quality == "1920x1080")
    }

    // MARK: - Proxy URLs

    @Test("The sources of a title are listed at /providers/")
    func streamsURL() {
        #expect(DispatcharrVODRequest.streamsURL(baseURL: base, kind: .movies, id: 42)?.absoluteString
                == "\(base)/api/vod/movies/42/providers/")
        #expect(DispatcharrVODRequest.streamsURL(baseURL: base, kind: .series, id: 7)?.absoluteString
                == "\(base)/api/vod/series/7/providers/")
    }

    @Test("A chosen movie stream is asked for by stream id and account")
    func movieStreamQuery() {
        let stream = VODStream(id: 12, accountId: 3, accountName: "Strong", streamId: "771230")
        #expect(DispatcharrVODRequest.movieStreamURL(baseURL: base, uuid: "abc", stream: stream)?.absoluteString
                == "\(base)/proxy/vod/movie/abc?stream_id=771230&m3u_account_id=3")
    }

    @Test("A series source is asked for by account, and no choice leaves the URL as it was")
    func episodeStreamQuery() {
        let source = VODStream(id: 5, accountId: 2, accountName: "Backup")
        #expect(DispatcharrVODRequest.episodeStreamURL(baseURL: base, uuid: "ep", stream: source)?.absoluteString
                == "\(base)/proxy/vod/episode/ep?m3u_account_id=2")
        #expect(DispatcharrVODRequest.episodeStreamURL(baseURL: base, uuid: "ep", stream: nil)?.absoluteString
                == "\(base)/proxy/vod/episode/ep")
    }

    // MARK: - The detail page

    private let movie = VODItem(itemId: 1, uuid: "movie-1", name: "Movie", kind: .movies)

    private func makeModel(streams: [VODStream]) -> (VODDetailViewModel, FakeVODProvider) {
        let provider = FakeVODProvider()
        provider.movieDetails[1] = VODMovieDetail(id: 1, uuid: "movie-1", name: "Movie")
        provider.streams[1] = streams
        let suite = "VODStreamTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (VODDetailViewModel(item: movie, provider: provider, defaults: defaults), provider)
    }

    @Test("Two sources or more offer a choice, starting on Automatic")
    func offersChoice() async {
        let streams = [
            VODStream(id: 1, accountId: 1, accountName: "Main", streamId: "10"),
            VODStream(id: 2, accountId: 2, accountName: "Backup", streamId: "20")
        ]
        let (model, _) = makeModel(streams: streams)
        await model.load()

        #expect(model.streams == streams)
        #expect(model.selectedStream == nil)
        model.selectedStreamId = 2
        #expect(model.selectedStream?.accountName == "Backup")
    }

    @Test("A single source, or a list that can't be read, offers nothing")
    func noChoice() async {
        let (single, _) = makeModel(streams: [VODStream(id: 1, accountId: 1, accountName: "Main", streamId: "10")])
        await single.load()
        #expect(single.streams.isEmpty)

        let (failing, provider) = makeModel(streams: [])
        provider.streamsError = PVRClientError.invalidResponse
        await failing.load()
        #expect(failing.streams.isEmpty)
        #expect(failing.error == nil, "the page itself still loads")
    }

    @Test("A choice that disappears on reload goes back to Automatic")
    func staleChoice() async {
        let (model, provider) = makeModel(streams: [
            VODStream(id: 1, accountId: 1, accountName: "Main", streamId: "10"),
            VODStream(id: 2, accountId: 2, accountName: "Backup", streamId: "20")
        ])
        await model.load()
        model.selectedStreamId = 2

        provider.streams[1] = [
            VODStream(id: 1, accountId: 1, accountName: "Main", streamId: "10"),
            VODStream(id: 3, accountId: 3, accountName: "Other", streamId: "30")
        ]
        await model.load()

        #expect(model.selectedStreamId == nil)
    }
}
