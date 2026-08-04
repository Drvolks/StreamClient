//
//  LiveStreamKeepaliveTests.swift
//  NexusPVRTests
//
//  Tests for the channel.stream.info live stream renewal (issue #120).
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct LiveStreamKeepaliveTests {

    private func makeDemoClient() -> NextPVRClient {
        NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
    }

    @Test("Renewal is a no-op in demo mode")
    func renewIsNoOpInDemoMode() async throws {
        let client = makeDemoClient()
        try await client.authenticate()
        let info = try await client.renewLiveStream()
        #expect(info == nil)
    }

    @Test("Well-formed stream info parses")
    func parsesWellFormedResponse() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map>
          <stream_duration>134000</stream_duration>
          <stream_length>18874368</stream_length>
          <complete>false</complete>
        </map>
        """
        let info = NextPVRClient.parseStreamInfo(Data(xml.utf8))
        #expect(info?.streamDurationMs == 134_000)
        #expect(info?.streamLength == 18_874_368)
        #expect(info?.isComplete == false)
        #expect(info?.streamDuration == 134)
    }

    @Test("Completed stream is reported as complete")
    func parsesCompleteFlag() {
        let xml = """
        <map>
          <stream_duration>500</stream_duration>
          <stream_length>1000</stream_length>
          <complete>true</complete>
        </map>
        """
        #expect(NextPVRClient.parseStreamInfo(Data(xml.utf8))?.isComplete == true)
    }

    @Test("Missing complete element defaults to false")
    func missingCompleteDefaultsToFalse() {
        let xml = "<map><stream_duration>500</stream_duration><stream_length>1000</stream_length></map>"
        #expect(NextPVRClient.parseStreamInfo(Data(xml.utf8))?.isComplete == false)
    }

    @Test("Byte rate is derived from buffer length over duration")
    func computesByteRate() {
        // 100s of buffer holding 50MB → 500KB/s.
        let info = LiveStreamInfo(streamDurationMs: 100_000, streamLength: 50_000_000, isComplete: false)
        #expect(info.bytesPerSecond == 500_000)
        #expect(info.byteOffset(forPosition: 60) == 30_000_000)
        // Seeking to the start is byte 0, and negative positions clamp there.
        #expect(info.byteOffset(forPosition: 0) == 0)
        #expect(info.byteOffset(forPosition: -30) == 0)
    }

    @Test("Byte rate is unavailable until the buffer has content")
    func byteRateNeedsContent() {
        #expect(LiveStreamInfo(streamDurationMs: 0, streamLength: 0, isComplete: false).bytesPerSecond == nil)
        #expect(LiveStreamInfo(streamDurationMs: 0, streamLength: 500, isComplete: false).bytesPerSecond == nil)
        #expect(LiveStreamInfo(streamDurationMs: 5000, streamLength: 0, isComplete: false).bytesPerSecond == nil)
        #expect(LiveStreamInfo(streamDurationMs: 5000, streamLength: 0, isComplete: false).byteOffset(forPosition: 1) == nil)
    }

    @Test("Seek URL is nil without an active timeshift stream")
    func seekURLRequiresActiveStream() async throws {
        let client = makeDemoClient()
        try await client.authenticate()
        #expect(client.liveStreamSeekURL(byteOffset: 1000) == nil)
    }

    @Test("Malformed or empty bodies return nil rather than throwing")
    func malformedResponsesReturnNil() {
        #expect(NextPVRClient.parseStreamInfo(Data()) == nil)
        #expect(NextPVRClient.parseStreamInfo(Data("not xml at all".utf8)) == nil)
        #expect(NextPVRClient.parseStreamInfo(Data("<map><stream_duration>5".utf8)) == nil)
        // Well-formed but missing the fields we need.
        #expect(NextPVRClient.parseStreamInfo(Data("<map><complete>false</complete></map>".utf8)) == nil)
        // JSON error response (e.g. session expired) must not parse as stream info.
        #expect(NextPVRClient.parseStreamInfo(Data(#"{"stat":"fail"}"#.utf8)) == nil)
    }
}
