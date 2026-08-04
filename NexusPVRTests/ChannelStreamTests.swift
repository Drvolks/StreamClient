//
//  ChannelStreamTests.swift
//  NexusPVRTests
//
//  Tests for ChannelStream decoding and labelling (stream switcher, #116).
//

import Testing
import Foundation
@testable import NextPVR

struct ChannelStreamTests {

    // MARK: - Decoding

    @Test("Decodes the Dispatcharr stream payload")
    func decodesPayload() throws {
        let json = #"""
        {"id": 4021, "name": "TSN 1 FHD", "url": "http://x/1", "m3u_account": 3, "is_stale": false}
        """#
        let stream = try JSONDecoder().decode(ChannelStream.self, from: Data(json.utf8))
        #expect(stream.id == 4021)
        #expect(stream.name == "TSN 1 FHD")
        #expect(stream.m3uAccountId == 3)
        #expect(stream.isStale == false)
    }

    @Test("Decodes string id and string m3u_account")
    func decodesStringNumbers() throws {
        let json = #"{"id": "77", "name": "Alt", "m3u_account": "4"}"#
        let stream = try JSONDecoder().decode(ChannelStream.self, from: Data(json.utf8))
        #expect(stream.id == 77)
        #expect(stream.m3uAccountId == 4)
    }

    @Test("Decodes a nested m3u_account object")
    func decodesNestedAccount() throws {
        let json = #"{"id": 5, "name": "Alt", "m3u_account": {"id": 9, "name": "Provider"}}"#
        let stream = try JSONDecoder().decode(ChannelStream.self, from: Data(json.utf8))
        #expect(stream.m3uAccountId == 9)
    }

    @Test("Custom streams have no m3u_account")
    func decodesWithoutAccount() throws {
        let json = #"{"id": 5, "name": "Custom", "is_custom": true}"#
        let stream = try JSONDecoder().decode(ChannelStream.self, from: Data(json.utf8))
        #expect(stream.m3uAccountId == nil)
        #expect(stream.isStale == nil)
    }

    @Test("Unparsable id throws")
    func rejectsBadId() {
        let json = #"{"id": "abc", "name": "Bad"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ChannelStream.self, from: Data(json.utf8))
        }
    }

    // MARK: - Display

    @Test("Falls back to the stream id when unnamed")
    func displayNameFallback() {
        #expect(ChannelStream(id: 12, name: nil, m3uAccountId: nil).displayName == "Stream #12")
        #expect(ChannelStream(id: 12, name: "", m3uAccountId: nil).displayName == "Stream #12")
        #expect(ChannelStream(id: 12, name: "CBC HD", m3uAccountId: nil).displayName == "CBC HD")
    }

    @Test("Label appends the resolved M3U account name")
    func labelWithAccountName() {
        let stream = ChannelStream(id: 1, name: "CBC HD", m3uAccountId: 3)
        #expect(stream.label(accountNameLookup: { $0 == 3 ? "Provider" : nil }) == "CBC HD [Provider]")
    }

    @Test("Label falls back to the account id when unresolved")
    func labelWithUnknownAccount() {
        let stream = ChannelStream(id: 1, name: "CBC HD", m3uAccountId: 3)
        #expect(stream.label(accountNameLookup: { _ in nil }) == "CBC HD [M3U #3]")
        #expect(stream.label(accountNameLookup: nil) == "CBC HD [M3U #3]")
    }

    @Test("Label omits the account for custom streams")
    func labelWithoutAccount() {
        let stream = ChannelStream(id: 1, name: "Custom", m3uAccountId: nil)
        #expect(stream.label(accountNameLookup: { _ in "Provider" }) == "Custom")
    }
}
