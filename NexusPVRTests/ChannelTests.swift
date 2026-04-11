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
            logoURL: "http://logo"
        )
        #expect(ch.id == 1)
        #expect(ch.name == "Name")
        #expect(ch.number == 2)
        #expect(ch.hasIcon)
        #expect(ch.streamURL == "http://x")
        #expect(ch.groupId == 3)
        #expect(ch.logoURL == "http://logo")
    }
}
