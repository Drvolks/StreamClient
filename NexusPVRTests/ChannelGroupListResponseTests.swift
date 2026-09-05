//
//  ChannelGroupListResponseTests.swift
//  NexusPVRTests
//
//  Tests for decoding NextPVR's `channel.groups` payload (#158).
//

import Testing
import Foundation
@testable import NextPVR

struct ChannelGroupListResponseTests {

    private func decode(_ json: String) throws -> ChannelGroupListResponse {
        try JSONDecoder().decode(ChannelGroupListResponse.self, from: Data(json.utf8))
    }

    @Test("Decodes a bare array of group names")
    func decodesStringArray() throws {
        let response = try decode(#"{"groups": ["Sports", "News", "Kids"]}"#)
        #expect(response.groupNames == ["Sports", "News", "Kids"])
    }

    @Test("Decodes group objects carrying a name field")
    func decodesObjectArray() throws {
        let response = try decode(#"{"groups": [{"name": "Sports"}, {"name": "News"}]}"#)
        #expect(response.groupNames == ["Sports", "News"])
    }

    @Test("Decodes group objects using the groupName alias")
    func decodesGroupNameAlias() throws {
        let response = try decode(#"{"groups": [{"groupName": "Movies"}, {"group": "Local"}]}"#)
        #expect(response.groupNames == ["Movies", "Local"])
    }

    @Test("Ignores extra fields on group objects")
    func ignoresExtraFields() throws {
        let response = try decode(#"{"groups": [{"name": "Sports", "count": 12, "id": 3}]}"#)
        #expect(response.groupNames == ["Sports"])
    }

    @Test("Missing groups key decodes to no groups")
    func missingGroupsKey() throws {
        let response = try decode(#"{"stat": "ok"}"#)
        #expect(response.groupNames.isEmpty)
    }

    @Test("Empty groups array decodes to no groups")
    func emptyGroupsArray() throws {
        let response = try decode(#"{"groups": []}"#)
        #expect(response.groupNames.isEmpty)
    }

    @Test("Blank and duplicate names are dropped")
    func trimsAndDeduplicates() throws {
        let response = try decode(#"{"groups": ["  Sports  ", "", "   ", "Sports", "News"]}"#)
        #expect(response.groupNames == ["Sports", "News"])
    }

    @Test("A group entry without any name fails the decode")
    func entryWithoutNameThrows() {
        #expect(throws: (any Error).self) {
            try decode(#"{"groups": [{"count": 3}]}"#)
        }
    }
}
