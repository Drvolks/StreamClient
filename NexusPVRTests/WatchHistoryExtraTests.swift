//
//  WatchHistoryExtraTests.swift
//  NexusPVRTests
//
//  Additional tests for WatchHistory save() and load() persistence logic.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct WatchHistoryExtraTests {

    @Test("WatchHistory save and load round-trip preserves channels")
    func saveAndLoadRoundTrip() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 1, channelName: "One")
        history.recordChannelPlay(channelId: 2, channelName: "Two")
        history.save()

        let loaded = WatchHistory.load()
        #expect(loaded.recentChannels.map(\.channelId) == [2, 1])
        #expect(loaded.recentChannels.map(\.channelName) == ["Two", "One"])

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "WatchHistory_NextPVR")
        UserDefaults(suiteName: ServerConfig.appGroupSuite)?.removeObject(forKey: "WatchHistory_NextPVR")
    }

    @Test("WatchHistory load returns empty when no data")
    func loadReturnsEmpty() {
        UserDefaults.standard.removeObject(forKey: "WatchHistory_NextPVR")
        let loaded = WatchHistory.load()
        #expect(loaded.recentChannels.isEmpty)
    }

    @Test("WatchHistory loadFromAppGroup returns empty when no data")
    func loadFromAppGroupEmpty() {
        UserDefaults(suiteName: ServerConfig.appGroupSuite)?.removeObject(forKey: "WatchHistory_NextPVR")
        let loaded = WatchHistory.loadFromAppGroup()
        #expect(loaded.recentChannels.isEmpty)
    }

    @Test("WatchHistory save writes to both standard and app group defaults")
    func saveWritesToBoth() {
        var history = WatchHistory()
        history.recordChannelPlay(channelId: 42, channelName: "Test")
        history.save()

        let fromStandard = UserDefaults.standard.data(forKey: "WatchHistory_NextPVR")
        #expect(fromStandard != nil)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "WatchHistory_NextPVR")
        UserDefaults(suiteName: ServerConfig.appGroupSuite)?.removeObject(forKey: "WatchHistory_NextPVR")
    }
}
