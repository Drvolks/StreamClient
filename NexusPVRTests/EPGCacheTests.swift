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

    private func makeProgram(id: Int, start: Date) -> Program {
        Program(
            id: id,
            name: "Program \(id)",
            subtitle: nil,
            desc: nil,
            start: Int(start.timeIntervalSince1970),
            end: Int(start.addingTimeInterval(3600).timeIntervalSince1970),
            genres: nil,
            channelId: id
        )
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

    // MARK: - EPG generation (#141)

    @Test("epgGeneration starts at zero and advances when the EPG is replaced")
    func epgGenerationAdvancesOnMutation() {
        let cache = EPGCache()
        #expect(cache.epgGeneration == 0)

        // invalidate() reassigns `epg`, which is what consumers key their
        // memoized slices on.
        cache.invalidate()
        #expect(cache.epgGeneration > 0)
    }

    // MARK: - Refresh

    @Test("refresh keeps cached data when the server is not configured")
    func refreshUnconfiguredKeepsData() async {
        let cache = EPGCache()
        cache.channels = makeChannels()
        cache.visibleChannels = makeChannels()

        await cache.refresh(using: PVRClient(config: ServerConfig(host: "", pin: "", useHTTPS: false)))

        // Unlike reloadData (which invalidates first), refresh must never blank
        // the grid — the user keeps seeing the channels they had.
        #expect(cache.channels.count == 3)
        #expect(cache.visibleChannels.count == 3)
        #expect(cache.error != nil)
        #expect(cache.isRefreshing == false)
    }

    @Test("isRefreshing initially false")
    func isRefreshingInitiallyFalse() {
        let cache = EPGCache()
        #expect(cache.isRefreshing == false)
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

    // MARK: - Name-based channel groups (#158)

    @Test("channels(inGroup:) matches multi-group membership")
    func channelsInGroupMatchesGroupIds() {
        let cache = EPGCache()
        cache.visibleChannels = [
            Channel(id: 1, name: "A", number: 1, groupIds: [30, 40]),
            Channel(id: 2, name: "B", number: 2, groupIds: [40]),
            Channel(id: 3, name: "C", number: 3)
        ]
        #expect(cache.channels(inGroup: 30).map(\.id) == [1])
        #expect(cache.channels(inGroup: 40).map(\.id) == [1, 2])
        #expect(cache.channels(inGroup: 50).isEmpty)
        #expect(cache.channels(inGroup: nil).count == 3)
    }

    #if !DISPATCHERPVR
    private func makeUngroupedChannels() -> [Channel] {
        [
            Channel(id: 1, name: "Sports One", number: 1),
            Channel(id: 2, name: "News One", number: 2),
            Channel(id: 3, name: "Movie One", number: 3)
        ]
    }

    private func populate(_ cache: EPGCache, with channels: [Channel]) {
        cache.channels = channels
        cache.visibleChannels = channels
        cache.applyChannelGroups(.empty)
    }

    @Test("applyChannelGroups publishes groups and stamps membership")
    func applyChannelGroupsStampsMembership() {
        let sports = ChannelGroup(name: "Sports")
        let news = ChannelGroup(name: "News")
        let cache = EPGCache()
        populate(cache, with: makeUngroupedChannels())

        cache.applyChannelGroups(
            ChannelGroupCatalog(
                groups: [sports, news],
                channelIdsByGroupId: [sports.id: [1, 2], news.id: [2]]
            )
        )

        #expect(cache.channelGroups.map(\.name) == ["Sports", "News"])
        #expect(cache.channels(inGroup: sports.id).map(\.id) == [1, 2])
        #expect(cache.channels(inGroup: news.id).map(\.id) == [2])
        #expect(cache.channelMap[2]?.groupIds == [sports.id, news.id])
    }

    @Test("applyChannelGroups keeps the unfiltered channel catalogue intact")
    func applyChannelGroupsKeepsAllChannels() {
        let sports = ChannelGroup(name: "Sports")
        let cache = EPGCache()
        populate(cache, with: makeUngroupedChannels())

        cache.applyChannelGroups(
            ChannelGroupCatalog(groups: [sports], channelIdsByGroupId: [sports.id: [1]])
        )

        #expect(cache.channels.count == 3)
        #expect(cache.visibleChannels.count == 3)
        #expect(cache.channels(inGroup: nil).count == 3)
    }

    @Test("An empty catalogue leaves the all-channel view working")
    func emptyCatalogueFallsBackToAllChannels() {
        let cache = EPGCache()
        populate(cache, with: makeUngroupedChannels())

        cache.applyChannelGroups(.empty)

        #expect(cache.channelGroups.isEmpty)
        #expect(cache.channels(inGroup: nil).count == 3)
        #expect(cache.channels.allSatisfy { $0.groupIds.isEmpty })
    }

    @Test("Re-applying groups replaces memberships removed server-side")
    func reapplyingGroupsDropsStaleMembership() {
        let sports = ChannelGroup(name: "Sports")
        let news = ChannelGroup(name: "News")
        let cache = EPGCache()
        populate(cache, with: makeUngroupedChannels())

        cache.applyChannelGroups(
            ChannelGroupCatalog(groups: [sports, news], channelIdsByGroupId: [sports.id: [1, 2], news.id: [2]])
        )
        // A refresh finds channel 2 moved out of Sports and News deleted.
        cache.applyChannelGroups(
            ChannelGroupCatalog(groups: [sports], channelIdsByGroupId: [sports.id: [1]])
        )

        #expect(cache.channelGroups.map(\.name) == ["Sports"])
        #expect(cache.channels(inGroup: sports.id).map(\.id) == [1])
        #expect(cache.channels(inGroup: news.id).isEmpty)
        #expect(cache.channelMap[2]?.groupIds.isEmpty == true)
    }

    @Test("Groups reported with no channels stay listed but match nothing")
    func emptyGroupMatchesNoChannels() {
        let empty = ChannelGroup(name: "Empty")
        let cache = EPGCache()
        populate(cache, with: makeUngroupedChannels())

        cache.applyChannelGroups(
            ChannelGroupCatalog(groups: [empty], channelIdsByGroupId: [empty.id: []])
        )

        #expect(cache.channelGroups.count == 1)
        #expect(cache.channels(inGroup: empty.id).isEmpty)
    }

    #endif

    // MARK: - Program Access

    @Test("earliestProgramDate finds the oldest EPG entry across channels")
    func earliestProgramDateAcrossChannels() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = now.addingTimeInterval(-3 * 86_400)
        let listings = [
            1: [makeProgram(id: 1, start: now)],
            2: [makeProgram(id: 2, start: oldest), makeProgram(id: 3, start: now.addingTimeInterval(-86_400))]
        ]

        #expect(EPGCache.earliestProgramDate(in: listings) == oldest)
        #expect(EPGCache.earliestProgramDate(in: [:]) == nil)
    }

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
