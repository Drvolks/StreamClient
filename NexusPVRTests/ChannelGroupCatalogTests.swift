//
//  ChannelGroupCatalogTests.swift
//  NexusPVRTests
//
//  Tests for the group/membership catalogue shared by the cache (#158).
//

import Testing
import Foundation
@testable import NextPVR

struct ChannelGroupCatalogTests {

    private let sports = ChannelGroup(name: "Sports")
    private let news = ChannelGroup(name: "News")
    private let empty = ChannelGroup(name: "Empty")

    @Test("Membership is inverted from each group's channel ids")
    func invertsMembership() {
        let catalog = ChannelGroupCatalog(
            groups: [sports, news],
            channelIdsByGroupId: [sports.id: [1, 2], news.id: [3]]
        )
        #expect(catalog.membership[1] == [sports.id])
        #expect(catalog.membership[2] == [sports.id])
        #expect(catalog.membership[3] == [news.id])
    }

    @Test("A channel in several groups keeps every membership")
    func multiGroupMembership() {
        let catalog = ChannelGroupCatalog(
            groups: [sports, news],
            channelIdsByGroupId: [sports.id: [1], news.id: [1]]
        )
        #expect(catalog.membership[1] == [sports.id, news.id])
    }

    @Test("Duplicate channel ids inside a group collapse")
    func duplicateMembershipCollapses() {
        let catalog = ChannelGroupCatalog(
            groups: [sports],
            channelIdsByGroupId: [sports.id: [1, 1, 1]]
        )
        #expect(catalog.membership[1] == [sports.id])
    }

    @Test("An empty group is still listed but owns no channels")
    func emptyGroupIsListed() {
        let catalog = ChannelGroupCatalog(
            groups: [sports, empty],
            channelIdsByGroupId: [sports.id: [1], empty.id: []]
        )
        #expect(catalog.groups.count == 2)
        #expect(catalog.channelIds(inGroup: empty.id).isEmpty)
        #expect(catalog.channelIds(inGroup: sports.id) == [1])
    }

    @Test("Channel ids for a group the server never reported are empty")
    func unknownGroupHasNoChannels() {
        let catalog = ChannelGroupCatalog(groups: [sports], channelIdsByGroupId: [sports.id: [1]])
        #expect(catalog.channelIds(inGroup: news.id).isEmpty)
    }

    @Test("The empty catalogue reports itself as empty")
    func emptyCatalogue() {
        #expect(ChannelGroupCatalog.empty.isEmpty)
        #expect(ChannelGroupCatalog.empty.groups.isEmpty)
        #expect(ChannelGroupCatalog.empty.membership.isEmpty)
    }

    @Test("Membership for groups with no reported ids is absent, not empty")
    func missingGroupEntry() {
        let catalog = ChannelGroupCatalog(groups: [sports, news], channelIdsByGroupId: [sports.id: [1]])
        #expect(catalog.membership[1] == [sports.id])
        #expect(catalog.membership.count == 1)
    }
}
