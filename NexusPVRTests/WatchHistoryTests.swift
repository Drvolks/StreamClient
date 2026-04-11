//
//  WatchHistoryTests.swift
//  NexusPVRTests
//
//  Tests for WatchHistory.recordChannelPlay semantics (in-memory only).
//

import Testing
@testable import NextPVR

struct WatchHistoryTests {

    @Test("recordChannelPlay inserts first channel at index 0")
    func insertsNewChannel() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 1, channelName: "One")
        #expect(history.recentChannels.map(\.channelId) == [1])
    }

    @Test("recordChannelPlay inserts newest at front")
    func orderingIsMostRecentFirst() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 1, channelName: "One")
        history.recordChannelPlay(channelId: 2, channelName: "Two")
        #expect(history.recentChannels.map(\.channelId) == [2, 1])
    }

    @Test("recordChannelPlay moves existing channel to front instead of duplicating")
    func deduplicatesExistingChannel() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 1, channelName: "One")
        history.recordChannelPlay(channelId: 2, channelName: "Two")
        history.recordChannelPlay(channelId: 1, channelName: "One")
        #expect(history.recentChannels.map(\.channelId) == [1, 2])
    }

    @Test("recordChannelPlay caps history at 4 entries")
    func capsAtFour() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 1, channelName: "One")
        history.recordChannelPlay(channelId: 2, channelName: "Two")
        history.recordChannelPlay(channelId: 3, channelName: "Three")
        history.recordChannelPlay(channelId: 4, channelName: "Four")
        history.recordChannelPlay(channelId: 5, channelName: "Five")
        #expect(history.recentChannels.count == 4)
        #expect(history.recentChannels.map(\.channelId) == [5, 4, 3, 2])
    }

    @Test("recordChannelPlay updates channelName when re-recording")
    func updatesChannelName() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 1, channelName: "Old")
        history.recordChannelPlay(channelId: 1, channelName: "New")
        #expect(history.recentChannels.first?.channelName == "New")
    }
}
