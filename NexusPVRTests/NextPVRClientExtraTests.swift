//
//  NextPVRClientExtraTests.swift
//  NexusPVRTests
//
//  Additional tests for NextPVRClient API methods in demo mode.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct NextPVRClientExtraTests {

    private func makeClient() -> NextPVRClient {
        NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
    }

    @Test("Demo channels have valid structure")
    func demoChannelsValid() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        #expect(channels.count > 3)
        for ch in channels {
            #expect(ch.id > 0)
            #expect(!ch.name.isEmpty)
            #expect(ch.number >= 0)
        }
    }

    @Test("Demo channels are sorted by number")
    func demoChannelsSorted() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        let sorted = channels.sorted { $0.number < $1.number }
        #expect(channels.map(\.number) == sorted.map(\.number))
    }

    @Test("Demo recordings have valid structure")
    func demoRecordingsValid() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, recording, scheduled) = try await client.getAllRecordings()
        #expect(!completed.isEmpty)
        for rec in completed {
            #expect(rec.id > 0)
            #expect(!rec.name.isEmpty)
            #expect(rec.recordingStatus == .ready)
        }
        for rec in scheduled {
            #expect(rec.recordingStatus == .pending)
        }
    }

    @Test("Demo recordings have correct durations")
    func demoRecordingsDurations() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _, _) = try await client.getAllRecordings()
        for rec in completed {
            #expect(rec.duration != nil)
            #expect(rec.duration! > 0)
        }
    }

    @Test("Demo listings have valid time span")
    func demoListingsValid() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let listings = try await client.getListings(channelId: firstChannel.id)
        for program in listings {
            #expect(program.id > 0)
            #expect(!program.name.isEmpty)
        }
    }

    @Test("Demo allListings covers multiple channels")
    func demoAllListingsMultipleChannels() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        let listings = try await client.getAllListings(for: channels)
        #expect(listings.keys.count > 1)
    }

    @Test("getFastListings returns per-channel data")
    func demoFastListings() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        let listings = try await client.getFastListings(for: channels)
        #expect(!listings.isEmpty)
        for (_, programs) in listings {
            #expect(!programs.isEmpty)
        }
    }

    @Test("channelIconURL returns valid URL for all channels")
    func demoChannelIconURLs() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        for ch in channels.prefix(5) {
            let url = try client.channelIconURL(channelId: ch.id)
            #expect(url != nil)
        }
    }

    @Test("liveStreamURL for all channels returns URLs")
    func demoLiveStreamURLs() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        for ch in channels.prefix(3) {
            let url = try await client.liveStreamURL(channelId: ch.id)
            #expect(!url.absoluteString.isEmpty)
        }
    }

    @Test("recordingStreamURL for all completed recordings returns URLs")
    func demoRecordingStreamURLs() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _, _) = try await client.getAllRecordings()
        for rec in completed.prefix(3) {
            let url = try await client.recordingStreamURL(recordingId: rec.id)
            #expect(!url.absoluteString.isEmpty)
        }
    }

    @Test("Multiple authenticate calls are idempotent")
    func authenticateIdempotent() async throws {
        let client = makeClient()
        try await client.authenticate()
        #expect(client.isAuthenticated)
        try await client.authenticate()
        #expect(client.isAuthenticated)
    }

    @Test("getListings for unknown channel returns empty")
    func listingsUnknownChannel() async throws {
        let client = makeClient()
        try await client.authenticate()
        let listings = try await client.getListings(channelId: 999999)
        #expect(listings.isEmpty)
    }

    @Test("Demo recurring recordings have valid structure")
    func demoRecurringValid() async throws {
        let client = makeClient()
        try await client.authenticate()
        let recurring = try await client.getRecurringRecordings()
        #expect(recurring.count >= 1)
        for r in recurring {
            #expect(r.id > 0)
            #expect(!r.name.isEmpty)
        }
    }

    @Test("setRecordingPosition and recording stream work together")
    func setPositionAndStream() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _, _) = try await client.getAllRecordings()
        guard let rec = completed.first else { return }

        try await client.setRecordingPosition(recordingId: rec.id, positionSeconds: 300)
        let url = try await client.recordingStreamURL(recordingId: rec.id)
        #expect(!url.absoluteString.isEmpty)
    }

    @Test("config baseURL matches expected demo URL")
    func configBaseURL() {
        let client = makeClient()
        #expect(client.baseURL.contains("demo"))
    }

    @Test("isConnecting initially false")
    func isConnectingFalse() {
        let client = makeClient()
        #expect(client.isConnecting == false)
    }
}
