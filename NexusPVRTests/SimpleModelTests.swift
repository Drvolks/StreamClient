//
//  SimpleModelTests.swift
//  NexusPVRTests
//
//  Tests for small models and enums: PlayerStats, SubtitleMode, GPUAPI,
//  ChannelGroup, ChannelProfile, RecordingsFilter, WatchedChannel.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct SimpleModelTests {

    // MARK: - PlayerStats

    @Test("PlayerStats default initializer zeroes all fields")
    func playerStatsDefault() {
        let stats = PlayerStats()
        #expect(stats.avgFps == 0)
        #expect(stats.avgBitrateKbps == 0)
        #expect(stats.totalDroppedFrames == 0)
        #expect(stats.totalDecoderDroppedFrames == 0)
        #expect(stats.totalVoDelayedFrames == 0)
        #expect(stats.maxAvsync == 0)
    }

    @Test("PlayerStats Codable round-trip preserves all fields")
    func playerStatsRoundTrip() throws {
        var stats = PlayerStats()
        stats.avgFps = 59.94
        stats.avgBitrateKbps = 12_000
        stats.totalDroppedFrames = 17
        stats.totalDecoderDroppedFrames = 3
        stats.totalVoDelayedFrames = 9
        stats.maxAvsync = 0.042

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(PlayerStats.self, from: data)
        #expect(decoded.avgFps == stats.avgFps)
        #expect(decoded.avgBitrateKbps == stats.avgBitrateKbps)
        #expect(decoded.totalDroppedFrames == stats.totalDroppedFrames)
        #expect(decoded.totalDecoderDroppedFrames == stats.totalDecoderDroppedFrames)
        #expect(decoded.totalVoDelayedFrames == stats.totalVoDelayedFrames)
        #expect(decoded.maxAvsync == stats.maxAvsync)
    }

    @Test("PlayerStats requires all fields when decoding (no custom init(from:))")
    func playerStatsStrictDecode() {
        // PlayerStats uses the synthesized Codable conformance, which requires
        // every var-with-default to be present in the JSON. This test pins that
        // behavior so a future switch to a custom init(from:) would be caught.
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PlayerStats.self, from: Data(#"{"avgFps": 30}"#.utf8))
        }
    }

    // MARK: - SubtitleMode

    @Test("SubtitleMode round-trips via raw value and Codable")
    func subtitleModeCodable() throws {
        for mode in SubtitleMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SubtitleMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("SubtitleMode has manual and auto cases")
    func subtitleModeCases() {
        #expect(SubtitleMode.allCases.contains(.manual))
        #expect(SubtitleMode.allCases.contains(.auto))
        #expect(SubtitleMode.allCases.count == 2)
    }

    // MARK: - GPUAPI

    @Test("GPUAPI round-trips via raw value and Codable")
    func gpuAPICodable() throws {
        for api in GPUAPI.allCases {
            let data = try JSONEncoder().encode(api)
            let decoded = try JSONDecoder().decode(GPUAPI.self, from: data)
            #expect(decoded == api)
        }
    }

    @Test("GPUAPI covers metal, opengl, and pixelbuffer")
    func gpuAPICases() {
        #expect(GPUAPI.allCases.contains(.metal))
        #expect(GPUAPI.allCases.contains(.opengl))
        #expect(GPUAPI.allCases.contains(.pixelbuffer))
        #expect(GPUAPI.allCases.count == 3)
    }

    // MARK: - ChannelGroup

    @Test("ChannelGroup decodes id and name")
    func channelGroupDecode() throws {
        let json = #"{"id": 3, "name": "Sports"}"#
        let g = try JSONDecoder().decode(ChannelGroup.self, from: Data(json.utf8))
        #expect(g.id == 3)
        #expect(g.name == "Sports")
    }

    // MARK: - ChannelProfile

    @Test("ChannelProfile decodes id, name, and channels list")
    func channelProfileDecode() throws {
        let json = #"{"id": 1, "name": "Favorites", "channels": [10, 20, 30]}"#
        let p = try JSONDecoder().decode(ChannelProfile.self, from: Data(json.utf8))
        #expect(p.id == 1)
        #expect(p.name == "Favorites")
        #expect(p.channels == [10, 20, 30])
    }

    @Test("ChannelProfile decodes empty channels array")
    func channelProfileEmpty() throws {
        let json = #"{"id": 2, "name": "None", "channels": []}"#
        let p = try JSONDecoder().decode(ChannelProfile.self, from: Data(json.utf8))
        #expect(p.channels.isEmpty)
    }

    // MARK: - RecordingsFilter

    @Test("RecordingsFilter raw values match labels")
    func recordingsFilterRawValues() {
        #expect(RecordingsFilter.completed.rawValue == "Completed")
        #expect(RecordingsFilter.recording.rawValue == "Recording")
        #expect(RecordingsFilter.scheduled.rawValue == "Scheduled")
    }

    @Test("RecordingsFilter identifier equals raw value")
    func recordingsFilterIdentifier() {
        #expect(RecordingsFilter.completed.id == "Completed")
        #expect(RecordingsFilter.scheduled.id == "Scheduled")
    }

    // MARK: - WatchedChannel

    @Test("WatchedChannel is Codable and Equatable")
    func watchedChannelCodable() throws {
        let a = WatchedChannel(channelId: 5, channelName: "ABC")
        let b = WatchedChannel(channelId: 5, channelName: "ABC")
        #expect(a == b)

        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(WatchedChannel.self, from: data)
        #expect(decoded == a)
    }
}
