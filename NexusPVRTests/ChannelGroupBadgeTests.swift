//
//  ChannelGroupBadgeTests.swift
//  NexusPVRTests
//

import Testing
@testable import NextPVR

struct ChannelGroupBadgeTests {
    private let all = ChannelGroup(name: "All Channels")
    private let sports = ChannelGroup(name: "Sports")
    private let tsn = ChannelGroup(name: "TSN")

    private var channels: [Channel] {
        [
            Channel(id: 1, name: "TSN 1", number: 1, groupIds: [all.id, sports.id, tsn.id]),
            Channel(id: 2, name: "TSN 2", number: 2, groupIds: [all.id, sports.id, tsn.id]),
            Channel(id: 3, name: "ESPN", number: 3, groupIds: [all.id, sports.id]),
            Channel(id: 4, name: "News", number: 4, groupIds: [all.id])
        ]
    }

    private func badge(for channel: Channel) -> String? {
        let groups = [all, sports, tsn]
        return ChannelGroupBadge.name(
            for: channel,
            groups: groups,
            sizes: ChannelGroupBadge.groupSizes(groups, in: channels),
            channelCount: channels.count
        )
    }

    @Test("Counts each group's channels")
    func sizes() {
        let sizes = ChannelGroupBadge.groupSizes([all, sports, tsn], in: channels)
        #expect(sizes[all.id] == 4)
        #expect(sizes[sports.id] == 3)
        #expect(sizes[tsn.id] == 2)
    }

    @Test("A group holding every channel, like NextPVR's All Channels, never names the badge")
    func catchAllIsSkipped() {
        #expect(badge(for: channels[2]) == "Sports")
        #expect(badge(for: channels[3]) == nil)
    }

    @Test("The smallest group the channel belongs to wins")
    func mostSpecificGroupWins() {
        #expect(badge(for: channels[0]) == "TSN")
    }

    @Test("A channel in no group has no badge")
    func noGroup() {
        #expect(badge(for: Channel(id: 9, name: "Loose", number: 9)) == nil)
    }
}
