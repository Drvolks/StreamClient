//
//  ChannelGroupTests.swift
//  NexusPVRTests
//
//  Tests for the name-based channel group identity NextPVR needs (#158).
//

import Testing
import Foundation
@testable import NextPVR

struct ChannelGroupTests {

    @Test("Group built from a name keeps the name and derives its id from it")
    func nameInitDerivesId() {
        let group = ChannelGroup(name: "Sports")
        #expect(group.name == "Sports")
        #expect(group.id == ChannelGroup.stableId(forName: "Sports"))
    }

    @Test("Stable ids are deterministic for the same name")
    func stableIdIsDeterministic() {
        // The ids are persisted in UserPreferences and synced via iCloud, so
        // they must not vary between runs the way String.hashValue does.
        #expect(ChannelGroup.stableId(forName: "News") == ChannelGroup.stableId(forName: "News"))
        #expect(ChannelGroup.stableId(forName: "News") == 1_274_284_134)
        #expect(ChannelGroup.stableId(forName: "Kids") == 889_456_028)
    }

    @Test("Different names get different ids")
    func distinctNamesDistinctIds() {
        let names = ["Sports", "News", "Kids", "Movies", "Local", "Français", ""]
        let ids = Set(names.map(ChannelGroup.stableId(forName:)))
        #expect(ids.count == names.count)
    }

    @Test("Stable ids are non-negative and fit in Int32")
    func stableIdRange() {
        for name in ["Sports", "News", "A very long channel group name ☃️", "z"] {
            let id = ChannelGroup.stableId(forName: name)
            #expect(id >= 0)
            #expect(id <= Int(Int32.max))
        }
    }

    @Test("Group name is case and whitespace sensitive")
    func namesAreDistinctByExactSpelling() {
        #expect(ChannelGroup.stableId(forName: "Sports") != ChannelGroup.stableId(forName: "sports"))
        #expect(ChannelGroup.stableId(forName: "Sports") != ChannelGroup.stableId(forName: "Sports "))
    }

    @Test("Explicit id initializer is unchanged for integer-id backends")
    func explicitIdInit() {
        let group = ChannelGroup(id: 7, name: "Entertainment")
        #expect(group.id == 7)
        #expect(group.name == "Entertainment")
    }

    @Test("Group decodes Dispatcharr's integer-id payload")
    func decodesIntegerIdPayload() throws {
        let json = #"{"id": 12, "name": "Documentary"}"#
        let group = try JSONDecoder().decode(ChannelGroup.self, from: Data(json.utf8))
        #expect(group.id == 12)
        #expect(group.name == "Documentary")
    }
}
