//
//  DispatcharrChannelTests.swift
//  NexusPVRTests
//
//  Tests for DispatcharrChannel's decode of Dispatcharr's channel API
//  shape, including the catch-up fields added for #119.
//

import Testing
import Foundation
@testable import NextPVR

struct DispatcharrChannelTests {

    @Test("Decodes is_catchup / catchup_days when the server sends them")
    func decodesCatchupFields() throws {
        let json = """
        {
            "id": 7,
            "name": "News",
            "channel_number": 7,
            "uuid": "abc-123",
            "is_catchup": true,
            "catchup_days": 5
        }
        """
        let ch = try JSONDecoder().decode(DispatcharrChannel.self, from: Data(json.utf8))
        #expect(ch.isCatchup)
        #expect(ch.catchupDays == 5)
    }

    @Test("Defaults is_catchup / catchup_days to off when the server omits them")
    func defaultsCatchupFieldsOff() throws {
        let json = """
        {
            "id": 7,
            "name": "News"
        }
        """
        let ch = try JSONDecoder().decode(DispatcharrChannel.self, from: Data(json.utf8))
        #expect(!ch.isCatchup)
        #expect(ch.catchupDays == 0)
    }

    @Test("toChannel() propagates catch-up fields")
    func toChannelPropagatesCatchup() throws {
        let json = """
        {
            "id": 7,
            "name": "News",
            "channel_number": 7,
            "is_catchup": true,
            "catchup_days": 3
        }
        """
        let ch = try JSONDecoder().decode(DispatcharrChannel.self, from: Data(json.utf8)).toChannel()
        #expect(ch.isCatchup)
        #expect(ch.catchupDays == 3)
    }
}
