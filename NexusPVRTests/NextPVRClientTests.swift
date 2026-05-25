//
//  NextPVRClientTests.swift
//  NexusPVRTests
//
//  Tests for NextPVRClient in demo mode — exercises API methods
//  that return pre-seeded data without network access.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct NextPVRClientTests {

    private func makeClient() -> NextPVRClient {
        NextPVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false))
    }

    @Test("Demo client is configured")
    func demoClientIsConfigured() {
        let client = makeClient()
        #expect(client.isConfigured == true)
    }

    @Test("Demo client is in demo mode")
    func demoClientIsDemoMode() {
        let client = makeClient()
        #expect(client.config.isDemoMode == true)
    }

    @Test("authenticate sets isAuthenticated without network")
    func authenticate() async throws {
        let client = makeClient()
        #expect(client.isAuthenticated == false)
        try await client.authenticate()
        #expect(client.isAuthenticated == true)
    }

    @Test("disconnect clears authentication")
    func disconnect() async throws {
        let client = makeClient()
        try await client.authenticate()
        #expect(client.isAuthenticated == true)
        client.disconnect()
        #expect(client.isAuthenticated == false)
    }

    @Test("getChannels returns pre-seeded demo channels")
    func getChannels() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        #expect(!channels.isEmpty)
        #expect(channels.allSatisfy { $0.id > 0 })
        #expect(channels.allSatisfy { !$0.name.isEmpty })
    }

    @Test("getListings returns programs for a channel")
    func getListings() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let listings = try await client.getListings(channelId: firstChannel.id)
        #expect(!listings.isEmpty)
    }

    @Test("getAllListings returns programs for all channels")
    func getAllListings() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        let listings = try await client.getAllListings(for: channels)
        #expect(!listings.isEmpty)
    }

    @Test("getFastListings returns fast-window programs")
    func getFastListings() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        let listings = try await client.getFastListings(for: channels)
        #expect(!listings.isEmpty)
    }

    @Test("getAllRecordings returns demo recordings with completed and scheduled")
    func getAllRecordings() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _ /* recording */, scheduled) = try await client.getAllRecordings()
        #expect(!completed.isEmpty)
        #expect(!scheduled.isEmpty)
    }

    @Test("liveStreamURL returns a demo stream URL")
    func liveStreamURL() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let url = try await client.liveStreamURL(channelId: firstChannel.id)
        #expect(url.absoluteString.hasSuffix(".mp4"))
    }

    @Test("recordingStreamURL returns a demo stream URL")
    func recordingStreamURL() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _, _) = try await client.getAllRecordings()
        guard let firstRecording = completed.first else { return }
        let url = try await client.recordingStreamURL(recordingId: firstRecording.id)
        #expect(url.absoluteString.hasSuffix(".mp4"))
    }

    @Test("scheduleRecording and cancelRecording are idempotent")
    func scheduleAndCancelRecording() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let listings = try await client.getListings(channelId: firstChannel.id)
        guard let program = listings.first else { return }

        try await client.scheduleRecording(eventId: program.id)
        try await client.cancelRecording(recordingId: program.id)
    }

    @Test("scheduleRecording with program and channel")
    func scheduleRecordingWithProgram() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let listings = try await client.getListings(channelId: firstChannel.id)
        guard let program = listings.first else { return }

        try await client.scheduleRecording(program: program, channel: firstChannel)
    }

    @Test("scheduleSeriesRecording and cancelSeriesRecording")
    func scheduleAndCancelSeries() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let listings = try await client.getListings(channelId: firstChannel.id)
        guard let program = listings.first else { return }

        try await client.scheduleSeriesRecording(eventId: program.id)
        try await client.cancelSeriesRecording(recurringId: program.id)
    }

    @Test("getRecurringRecordings returns pre-seeded entries")
    func getRecurringRecordings() async throws {
        let client = makeClient()
        try await client.authenticate()
        let recurring = try await client.getRecurringRecordings()
        #expect(!recurring.isEmpty)
    }

    @Test("setRecordingPosition completes without error")
    func setRecordingPosition() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _, _) = try await client.getAllRecordings()
        guard let rec = completed.first else { return }
        try await client.setRecordingPosition(recordingId: rec.id, positionSeconds: 120)
    }

    @Test("channelIconURL returns URL for a channel")
    func channelIconURL() async throws {
        let client = makeClient()
        try await client.authenticate()
        let channels = try await client.getChannels()
        guard let firstChannel = channels.first else { return }
        let url = try client.channelIconURL(channelId: firstChannel.id)
        #expect(url != nil)
    }

    @Test("recordingArtworkURL may return nil for some recordings")
    func recordingArtworkURL() async throws {
        let client = makeClient()
        try await client.authenticate()
        let (completed, _, _) = try await client.getAllRecordings()
        guard let rec = completed.first else { return }
        _ = client.recordingArtworkURL(recordingId: rec.id, fanart: false)
    }

    @Test("streamAuthHeaders returns a dictionary")
    func streamAuthHeaders() async throws {
        let client = makeClient()
        try await client.authenticate()
        let headers = client.streamAuthHeaders()
        _ = headers
    }

    @Test("updateConfig changes server configuration")
    func updateConfig() async throws {
        let client = makeClient()
        let newConfig = ServerConfig(host: "demo", port: 8866, pin: "", useHTTPS: false)
        client.updateConfig(newConfig)
        #expect(client.config.port == 8866)
    }
}
