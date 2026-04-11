//
//  RecurringRecordingTests.swift
//  NexusPVRTests
//
//  Tests for RecurringRecording custom Decodable priority logic.
//

import Testing
import Foundation
@testable import NextPVR

struct RecurringRecordingTests {

    @Test("Decodes using epgTitle in preference to name when both are present")
    func epgTitleBeatsName() throws {
        let json = #"{"id": 1, "epgTitle": "From EPG", "name": "From Name"}"#
        let rec = try JSONDecoder().decode(RecurringRecording.self, from: Data(json.utf8))
        #expect(rec.name == "From EPG")
    }

    @Test("Falls back to name when epgTitle is absent")
    func nameFallback() throws {
        let json = #"{"id": 2, "name": "Fallback Name"}"#
        let rec = try JSONDecoder().decode(RecurringRecording.self, from: Data(json.utf8))
        #expect(rec.name == "Fallback Name")
    }

    @Test("Optional channelID, channel, and enabled all default to nil when absent")
    func optionalsDefaultToNil() throws {
        let json = #"{"id": 3, "name": "Plain"}"#
        let rec = try JSONDecoder().decode(RecurringRecording.self, from: Data(json.utf8))
        #expect(rec.channelID == nil)
        #expect(rec.channel == nil)
        #expect(rec.enabled == nil)
    }

    @Test("Decodes all optional fields when present")
    func allFieldsPresent() throws {
        let json = #"{"id": 4, "name": "Full", "channelID": 7, "channel": "ABC", "enabled": true}"#
        let rec = try JSONDecoder().decode(RecurringRecording.self, from: Data(json.utf8))
        #expect(rec.channelID == 7)
        #expect(rec.channel == "ABC")
        #expect(rec.enabled == true)
    }

    @Test("Throws when neither epgTitle nor name is present")
    func throwsWhenNoTitle() {
        let json = #"{"id": 5}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RecurringRecording.self, from: Data(json.utf8))
        }
    }

    @Test("Memberwise initializer preserves all fields")
    func memberwiseInit() {
        let rec = RecurringRecording(id: 9, name: "X", channelID: 2, channel: "Ch", enabled: false)
        #expect(rec.id == 9)
        #expect(rec.name == "X")
        #expect(rec.channelID == 2)
        #expect(rec.channel == "Ch")
        #expect(rec.enabled == false)
    }
}
