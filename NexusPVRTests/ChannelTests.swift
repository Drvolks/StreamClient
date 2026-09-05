//
//  ChannelTests.swift
//  NexusPVRTests
//
//  Tests for Channel model Codable and helper methods.
//

import Testing
import Foundation
@testable import NextPVR

struct ChannelTests {

    @Test("Channel decodes API field names")
    func decodesAPIFields() throws {
        let json = """
        {
            "channelId": 42,
            "channelName": "ABC",
            "channelNumber": 7,
            "channelIcon": true,
            "channelDetails": "http://host/stream.ts"
        }
        """
        let ch = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))
        #expect(ch.id == 42)
        #expect(ch.name == "ABC")
        #expect(ch.number == 7)
        #expect(ch.hasIcon)
        #expect(ch.streamURL == "http://host/stream.ts")
    }

    @Test("Channel defaults missing number and hasIcon")
    func decodesMissingOptionalsAsDefaults() throws {
        let json = """
        {
            "channelId": 1,
            "channelName": "Test"
        }
        """
        let ch = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))
        #expect(ch.number == 0)
        #expect(ch.hasIcon == false)
        #expect(ch.streamURL == nil)
    }

    @Test("Channel trims whitespace from streamURL during decoding")
    func trimsStreamURL() throws {
        let json = """
        {
            "channelId": 1,
            "channelName": "Test",
            "channelDetails": "   http://host/stream.ts   "
        }
        """
        let ch = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))
        #expect(ch.streamURL == "http://host/stream.ts")
    }

    @Test("iconURL builds the NextPVR service URL")
    func iconURL_buildsServiceURL() {
        let ch = Channel(id: 5, name: "X", number: 1)
        let url = ch.iconURL(baseURL: "http://example.com")
        #expect(url?.absoluteString == "http://example.com/service?method=channel.icon&channel_id=5")
    }

    @Test("Memberwise init preserves all fields")
    func memberwiseInit() {
        let ch = Channel(
            id: 1,
            name: "Name",
            number: 2,
            hasIcon: true,
            streamURL: "http://x",
            groupId: 3,
            logoURL: "http://logo",
            isCatchup: true,
            catchupDays: 5
        )
        #expect(ch.id == 1)
        #expect(ch.name == "Name")
        #expect(ch.number == 2)
        #expect(ch.hasIcon)
        #expect(ch.streamURL == "http://x")
        #expect(ch.groupId == 3)
        #expect(ch.logoURL == "http://logo")
        #expect(ch.isCatchup)
        #expect(ch.catchupDays == 5)
    }

    @Test("Memberwise init defaults catch-up fields to off (#119)")
    func memberwiseInitDefaultsCatchupOff() {
        let ch = Channel(id: 1, name: "Name", number: 2)
        #expect(!ch.isCatchup)
        #expect(ch.catchupDays == 0)
    }

    @Test("Decoding NextPVR-shaped JSON always defaults catch-up fields off (#119)")
    func decodedChannelHasNoCatchup() throws {
        let json = """
        {
            "channelId": 1,
            "channelName": "Test"
        }
        """
        let ch = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))
        #expect(!ch.isCatchup)
        #expect(ch.catchupDays == 0)
    }
}

// MARK: - Group membership (#158)

struct ChannelGroupMembershipTests {

    @Test("A channel with no group data belongs to nothing")
    func noGroups() {
        let ch = Channel(id: 1, name: "A", number: 1)
        #expect(ch.groupIds.isEmpty)
        #expect(ch.isMember(ofGroup: 10) == false)
    }

    @Test("The single Dispatcharr groupId still counts as membership")
    func singleGroupIdIsMembership() {
        let ch = Channel(id: 1, name: "A", number: 1, groupId: 10)
        #expect(ch.isMember(ofGroup: 10))
        #expect(ch.isMember(ofGroup: 11) == false)
    }

    @Test("Multi-group membership matches any of the channel's groups")
    func multiGroupMembership() {
        let ch = Channel(id: 1, name: "A", number: 1, groupIds: [10, 20])
        #expect(ch.isMember(ofGroup: 10))
        #expect(ch.isMember(ofGroup: 20))
        #expect(ch.isMember(ofGroup: 30) == false)
    }

    @Test("withGroupIds replaces memberships and keeps every other field")
    func withGroupIdsPreservesFields() {
        let ch = Channel(
            id: 7,
            name: "Sports HD",
            number: 42,
            hasIcon: true,
            streamURL: "http://host/stream.ts",
            groupIds: [1],
            isCatchup: true,
            catchupDays: 3
        )
        let updated = ch.withGroupIds([2, 3])
        #expect(updated.groupIds == [2, 3])
        #expect(updated.id == 7)
        #expect(updated.name == "Sports HD")
        #expect(updated.number == 42)
        #expect(updated.hasIcon)
        #expect(updated.streamURL == "http://host/stream.ts")
        #expect(updated.isCatchup)
        #expect(updated.catchupDays == 3)
    }

    @Test("Decoded NextPVR channels start with no group memberships")
    func decodedChannelHasNoGroups() throws {
        let json = #"{"channelId": 1, "channelName": "A"}"#
        let ch = try JSONDecoder().decode(Channel.self, from: Data(json.utf8))
        #expect(ch.groupId == nil)
        #expect(ch.groupIds.isEmpty)
    }

    @Test("withCatchup carries group memberships through")
    func withCatchupPreservesGroups() {
        let ch = Channel(id: 1, name: "A", number: 1, groupId: 5, groupIds: [6])
        let updated = ch.withCatchup(isCatchup: true, catchupDays: 2)
        #expect(updated.groupId == 5)
        #expect(updated.groupIds == [6])
    }
}
