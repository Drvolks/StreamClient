//
//  EPGCacheTests.swift
//  NexusPVRTests
//
//  Tests for EPGCache channel filtering, program access, and invalidation
//  (non-network logic only).
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct EPGCacheTests {

    private func makeChannels() -> [Channel] {
        [
            Channel(id: 1, name: "ABC News", number: 1, groupId: 10),
            Channel(id: 2, name: "NBC Sports", number: 2, groupId: 10),
            Channel(id: 3, name: "CBS Drama", number: 3, groupId: 20)
        ]
    }

    // MARK: - Invalidation

    @Test("invalidate clears channel state")
    func invalidateClearsEverything() {
        let cache = EPGCache()
        cache.channels = makeChannels()
        cache.visibleChannels = makeChannels()
        cache.channelProfiles = [ChannelProfile(id: 1, name: "Test", channels: [1])]
        cache.channelGroups = [ChannelGroup(id: 1, name: "Sports")]

        cache.invalidate()

        #expect(cache.channels.isEmpty)
        #expect(cache.visibleChannels.isEmpty)
        #expect(cache.channelProfiles.isEmpty)
        #expect(cache.channelGroups.isEmpty)
        #expect(cache.hasLoaded == false)
        #expect(cache.isFullyLoaded == false)
    }

    // MARK: - Channel Filtering

    @Test("filteredChannels returns all when search is empty")
    func filteredChannelsEmptySearch() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        #expect(cache.filteredChannels(matching: "").count == 3)
    }

    @Test("filteredChannels filters by name")
    func filteredChannelsByName() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        let results = cache.filteredChannels(matching: "abc")
        #expect(results.count == 1)
        #expect(results.first?.name == "ABC News")
    }

    @Test("filteredChannels filters by name case-insensitively")
    func filteredChannelsByNameCaseInsensitive() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        let results = cache.filteredChannels(matching: "NEWS")
        #expect(results.count == 1)
        #expect(results.first?.name == "ABC News")
    }

    @Test("filteredChannels filters by number")
    func filteredChannelsByNumber() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        let results = cache.filteredChannels(matching: "2")
        #expect(results.count == 1)
        #expect(results.first?.number == 2)
    }

    @Test("filteredChannels returns all for text without match")
    func filteredChannelsNoMatch() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        let results = cache.filteredChannels(matching: "XYZ")
        #expect(results.isEmpty)
    }

    @Test("channels(inProfile:) returns all when profileId is nil")
    func channelsInProfileNil() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        #expect(cache.channels(inProfile: nil).count == 3)
    }

    @Test("channels(inProfile:) filters by profile channel IDs")
    func channelsInProfileFilters() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        cache.channelProfiles = [ChannelProfile(id: 1, name: "Favorites", channels: [1, 3])]
        let results = cache.channels(inProfile: 1)
        #expect(results.count == 2)
        #expect(results.map(\.id).sorted() == [1, 3])
    }

    @Test("channels(inProfile:) returns empty for non-matching profile")
    func channelsInProfileNoMatch() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        cache.channelProfiles = [ChannelProfile(id: 1, name: "Empty", channels: [999])]
        #expect(cache.channels(inProfile: 1).isEmpty)
    }

    @Test("channels(inProfile:) returns all for unknown profile ID")
    func channelsInProfileUnknown() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        #expect(cache.channels(inProfile: 99).count == 3)
    }

    @Test("channels(inGroup:) returns all when groupId is nil")
    func channelsInGroupNil() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        #expect(cache.channels(inGroup: nil).count == 3)
    }

    @Test("channels(inGroup:) filters by groupId")
    func channelsInGroupFilters() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        let results = cache.channels(inGroup: 10)
        #expect(results.count == 2)
        #expect(results.map(\.id).sorted() == [1, 2])
    }

    @Test("channels(inGroup:) returns empty for unknown groupId")
    func channelsInGroupUnknown() {
        let cache = EPGCache()
        cache.visibleChannels = makeChannels()
        #expect(cache.channels(inGroup: 99).isEmpty)
    }

    // MARK: - Program Access

    @Test("programs returns empty for unknown channel")
    func programsForUnknownChannel() {
        let cache = EPGCache()
        #expect(cache.programs(for: 999, on: Date()).isEmpty)
    }

    @Test("programs returns empty when EPG is not loaded")
    func programsReturnsEmptyWhenNotLoaded() {
        let cache = EPGCache()
        #expect(cache.programs(for: 1, on: Date()).isEmpty)
    }

    @Test("currentProgram returns nil when EPG is not loaded")
    func currentProgramNotLoaded() {
        let cache = EPGCache()
        #expect(cache.currentProgram(forChannelId: 1) == nil)
        #expect(cache.currentProgram(for: Channel(id: 1, name: "A", number: 1)) == nil)
    }

    @Test("currentProgram returns nil for unknown channel id")
    func currentProgramUnknownChannel() {
        let cache = EPGCache()
        #expect(cache.currentProgram(forChannelId: 999) == nil)
    }

    // MARK: - Search

    @Test("searchProgramsCount returns 0 for empty EPG")
    func searchProgramsCountEmpty() async {
        let cache = EPGCache()
        let count = await cache.searchProgramsCount(query: "news")
        #expect(count == 0)
    }

    // MARK: - Initial State

    @Test("isLoading initially false")
    func isLoadingInitiallyFalse() {
        let cache = EPGCache()
        #expect(cache.isLoading == false)
    }

    @Test("hasLoaded initially false")
    func hasLoadedInitiallyFalse() {
        let cache = EPGCache()
        #expect(cache.hasLoaded == false)
    }

    @Test("isFullyLoaded initially false")
    func isFullyLoadedInitiallyFalse() {
        let cache = EPGCache()
        #expect(cache.isFullyLoaded == false)
    }

    @Test("channels initially empty")
    func channelsInitiallyEmpty() {
        let cache = EPGCache()
        #expect(cache.channels.isEmpty)
    }

    @Test("visible channels initially empty")
    func visibleChannelsInitiallyEmpty() {
        let cache = EPGCache()
        #expect(cache.visibleChannels.isEmpty)
    }

    @Test("error initially nil")
    func errorInitiallyNil() {
        let cache = EPGCache()
        #expect(cache.error == nil)
    }

    @Test("channelMap initially empty")
    func channelMapInitiallyEmpty() {
        let cache = EPGCache()
        #expect(cache.channelMap.isEmpty)
    }
}
