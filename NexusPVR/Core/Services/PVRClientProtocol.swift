//
//  PVRClientProtocol.swift
//  PVR Client
//
//  Shared protocol for PVR API clients
//

import Foundation

@MainActor
protocol PVRClientProtocol: ObservableObject {
    var isAuthenticated: Bool { get }
    var isConnecting: Bool { get }
    var isConfigured: Bool { get }
    var config: ServerConfig { get }

    func authenticate() async throws
    func disconnect()
    func updateConfig(_ newConfig: ServerConfig)
    func getChannels() async throws -> [Channel]
    func getListings(channelId: Int) async throws -> [Program]
    func getAllListings(for channels: [Channel]) async throws -> [Int: [Program]]
    /// Fast first-paint EPG fetch — should return programs covering today (and ideally tomorrow).
    /// Default falls back to getAllListings; clients with a dedicated endpoint should override.
    func getFastListings(for channels: [Channel]) async throws -> [Int: [Program]]
    func getAllRecordings() async throws -> (completed: [Recording], recording: [Recording], scheduled: [Recording])
    func scheduleRecording(eventId: Int) async throws
    func scheduleRecording(program: Program, channel: Channel?) async throws
    func scheduleSeriesRecording(eventId: Int) async throws
    func cancelRecording(recordingId: Int) async throws
    func cancelSeriesRecording(recurringId: Int) async throws
    func getRecurringRecordings() async throws -> [RecurringRecording]
    func setRecordingPosition(recordingId: Int, positionSeconds: Int) async throws
    func liveStreamURL(channelId: Int) async throws -> URL
    /// Renew the server-side live stream handle so the backend doesn't reclaim the
    /// tuner while the client isn't reading (e.g. while paused). Returns the current
    /// timeshift buffer state when the backend reports it.
    /// Default is a no-op for backends that don't require renewals.
    func renewLiveStream() async throws -> LiveStreamInfo?
    /// Release any server-side live stream resources. Best-effort; must not throw.
    func stopLiveStream() async
    /// True while a server-side live stream handle is open. Callers that
    /// re-authenticate opportunistically must skip it while this holds: a new
    /// session orphans the handle that `/live` was opened under.
    var hasActiveLiveStream: Bool { get }
    /// URL replaying the live buffer from `byteOffset`, or nil when the backend
    /// has no seekable server-side buffer.
    func liveStreamSeekURL(byteOffset: Int64) -> URL?
    func recordingStreamURL(recordingId: Int) async throws -> URL
    func streamAuthHeaders() -> [String: String]
    func channelIconURL(channelId: Int) throws -> URL?
    func recordingArtworkURL(recordingId: Int, fanart: Bool) -> URL?
}

extension PVRClientProtocol {
    func scheduleRecording(program: Program, channel: Channel?) async throws {
        _ = channel
        try await scheduleRecording(eventId: program.id)
    }

    func getFastListings(for channels: [Channel]) async throws -> [Int: [Program]] {
        try await getAllListings(for: channels)
    }

    func renewLiveStream() async throws -> LiveStreamInfo? { nil }

    func stopLiveStream() async {}

    var hasActiveLiveStream: Bool { false }

    func liveStreamSeekURL(byteOffset: Int64) -> URL? { nil }
}
