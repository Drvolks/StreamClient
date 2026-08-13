//
//  PlayerStreamSwitcherTests.swift
//  NexusPVRTests
//
//  Tests for the player's stream picker state (#117).
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct PlayerStreamSwitcherTests {

    private func status(channelId: String, streamId: Int?) throws -> ProxyChannelStatus {
        let stream = streamId.map { "\($0)" } ?? "null"
        let json = #"""
        {"channel_id": "\#(channelId)", "channel_name": "TSN 1", "stream_id": \#(stream), "state": "active"}
        """#
        return try JSONDecoder().decode(ProxyChannelStatus.self, from: Data(json.utf8))
    }

    private func stream(_ id: Int, name: String, account: Int? = nil) -> ChannelStream {
        ChannelStream(id: id, name: name, m3uAccountId: account)
    }

    // MARK: - Reading the proxy status

    @Test("Takes the active stream from the playing channel's status entry")
    func readsActiveStream() throws {
        let switcher = PlayerStreamSwitcher()
        switcher.prepareForTesting(channelUUID: "uuid-1", streams: [stream(1, name: "A"), stream(2, name: "B")])

        try switcher.applyStatus([
            status(channelId: "uuid-other", streamId: 9),
            status(channelId: "uuid-1", streamId: 2)
        ])

        #expect(switcher.activeStreamId == 2)
    }

    @Test("Ignores a status response that doesn't include the playing channel")
    func ignoresUnrelatedStatus() throws {
        let switcher = PlayerStreamSwitcher()
        switcher.prepareForTesting(channelUUID: "uuid-1", streams: [stream(1, name: "A")])
        try switcher.applyStatus([status(channelId: "uuid-1", streamId: 1)])

        // The channel drops out of the status while the proxy restarts a source.
        try switcher.applyStatus([status(channelId: "uuid-other", streamId: 7)])

        #expect(switcher.activeStreamId == 1)
    }

    @Test("Reports no active stream before any status arrives")
    func noActiveStreamInitially() {
        let switcher = PlayerStreamSwitcher()
        switcher.prepareForTesting(channelUUID: "uuid-1", streams: [stream(1, name: "A")])

        #expect(switcher.activeStreamId == nil)
    }

    // MARK: - Pending selections

    @Test("A pending selection wins until the server reports it")
    func pendingSelectionWins() throws {
        let switcher = PlayerStreamSwitcher()
        switcher.prepareForTesting(channelUUID: "uuid-1", streams: [stream(1, name: "A"), stream(2, name: "B")])
        switcher.markPendingSelectionForTesting(2, at: Date())

        // Proxy still on the old source right after the switch.
        try switcher.applyStatus([status(channelId: "uuid-1", streamId: 1)])
        #expect(switcher.activeStreamId == 2)

        try switcher.applyStatus([status(channelId: "uuid-1", streamId: 2)])
        #expect(switcher.activeStreamId == 2)
        #expect(switcher.reportedStreamId == 2)
    }

    @Test("A pending selection that never lands expires")
    func pendingSelectionExpires() throws {
        let now = Date()
        let switcher = PlayerStreamSwitcher(now: { now })
        switcher.prepareForTesting(channelUUID: "uuid-1", streams: [stream(1, name: "A"), stream(2, name: "B")])
        // Selected well past the 20s timeout — a failed switch must not pin the
        // picker to a stream the server isn't playing.
        switcher.markPendingSelectionForTesting(2, at: now.addingTimeInterval(-60))

        try switcher.applyStatus([status(channelId: "uuid-1", streamId: 1)])

        #expect(switcher.activeStreamId == 1)
    }

    // MARK: - Labels

    @Test("Labels streams with their M3U account name")
    func labelsStreams() {
        let switcher = PlayerStreamSwitcher()
        switcher.prepareForTesting(
            channelUUID: "uuid-1",
            streams: [stream(1, name: "TSN 1 FHD", account: 3), stream(2, name: "Backup")],
            accountNames: [3: "Provider A"]
        )

        #expect(switcher.label(for: switcher.streams[0]) == "TSN 1 FHD [Provider A]")
        #expect(switcher.label(for: switcher.streams[1]) == "Backup")
    }

    // MARK: - Reset

    @Test("Reset clears the channel's state")
    func resetClearsState() throws {
        let switcher = PlayerStreamSwitcher()
        switcher.prepareForTesting(channelUUID: "uuid-1", streams: [stream(1, name: "A")])
        try switcher.applyStatus([status(channelId: "uuid-1", streamId: 1)])

        switcher.reset()

        #expect(switcher.streams.isEmpty)
        #expect(switcher.activeStreamId == nil)
        #expect(switcher.channelUUID == nil)
    }
}
