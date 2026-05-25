//
//  ResponseModelsTests.swift
//  NexusPVRTests
//
//  Tests for simple API response wrapper models:
//  ChannelListResponse, ProgramListingsResponse, RecordingListResponse,
//  RecurringRecordingListResponse, SessionInitiateResponse, SessionLoginResponse.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct ResponseModelsTests {

    // MARK: - ChannelListResponse

    @Test("ChannelListResponse decodes channels array")
    func channelListDecode() throws {
        let json = """
        {
            "channels": [
                {"channelId": 1, "channelName": "One"},
                {"channelId": 2, "channelName": "Two"}
            ]
        }
        """
        let resp = try JSONDecoder().decode(ChannelListResponse.self, from: Data(json.utf8))
        #expect(resp.channels?.count == 2)
        #expect(resp.channels?[0].id == 1)
        #expect(resp.channels?[0].name == "One")
    }

    @Test("ChannelListResponse decodes nil channels")
    func channelListDecodeNil() throws {
        let json = "{}"
        let resp = try JSONDecoder().decode(ChannelListResponse.self, from: Data(json.utf8))
        #expect(resp.channels == nil)
    }

    // MARK: - ProgramListingsResponse

    @Test("ProgramListingsResponse decodes listings array")
    func programListingsDecode() throws {
        let json = """
        {
            "listings": [
                {"id": 100, "name": "News", "start": 1718400000, "end": 1718403600}
            ]
        }
        """
        let resp = try JSONDecoder().decode(ProgramListingsResponse.self, from: Data(json.utf8))
        #expect(resp.listings?.count == 1)
        #expect(resp.listings?[0].id == 100)
        #expect(resp.listings?[0].name == "News")
    }

    @Test("ProgramListingsResponse decodes nil listings")
    func programListingsDecodeNil() throws {
        let json = "{}"
        let resp = try JSONDecoder().decode(ProgramListingsResponse.self, from: Data(json.utf8))
        #expect(resp.listings == nil)
    }

    // MARK: - RecordingListResponse

    @Test("RecordingListResponse decodes recordings array")
    func recordingListDecode() throws {
        let json = """
        {
            "recordings": [
                {"id": 1, "name": "Movie", "startTime": 1718400000, "status": "ready"}
            ]
        }
        """
        let resp = try JSONDecoder().decode(RecordingListResponse.self, from: Data(json.utf8))
        #expect(resp.recordings?.count == 1)
        #expect(resp.recordings?[0].id == 1)
        #expect(resp.recordings?[0].name == "Movie")
    }

    @Test("RecordingListResponse decodes nil recordings")
    func recordingListDecodeNil() throws {
        let json = "{}"
        let resp = try JSONDecoder().decode(RecordingListResponse.self, from: Data(json.utf8))
        #expect(resp.recordings == nil)
    }

    // MARK: - RecurringRecordingListResponse

    @Test("RecurringRecordingListResponse decodes recurrings array")
    func recurringListDecode() throws {
        let json = """
        {
            "recurrings": [
                {"id": 5, "name": "Daily Show"}
            ]
        }
        """
        let resp = try JSONDecoder().decode(RecurringRecordingListResponse.self, from: Data(json.utf8))
        #expect(resp.recurrings?.count == 1)
        #expect(resp.recurrings?[0].id == 5)
    }

    @Test("RecurringRecordingListResponse decodes nil recurrings")
    func recurringListDecodeNil() throws {
        let json = "{}"
        let resp = try JSONDecoder().decode(RecurringRecordingListResponse.self, from: Data(json.utf8))
        #expect(resp.recurrings == nil)
    }

    // MARK: - SessionInitiateResponse

    @Test("SessionInitiateResponse decodes sid, salt, stat")
    func sessionInitiateDecode() throws {
        let json = """
        {
            "sid": "abc123",
            "salt": "xyz456",
            "stat": "ok"
        }
        """
        let resp = try JSONDecoder().decode(SessionInitiateResponse.self, from: Data(json.utf8))
        #expect(resp.sid == "abc123")
        #expect(resp.salt == "xyz456")
        #expect(resp.stat == "ok")
    }

    @Test("SessionInitiateResponse decodes nil sid and salt")
    func sessionInitiateDecodeNil() throws {
        let json = "{}"
        let resp = try JSONDecoder().decode(SessionInitiateResponse.self, from: Data(json.utf8))
        #expect(resp.sid == nil)
        #expect(resp.salt == nil)
        #expect(resp.stat == nil)
    }

    // MARK: - SessionLoginResponse

    @Test("SessionLoginResponse isSuccess returns true for 'ok' stat")
    func sessionLoginOkViaStat() throws {
        let json = #"{"stat": "ok"}"#
        let resp = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(json.utf8))
        #expect(resp.isSuccess == true)
    }

    @Test("SessionLoginResponse isSuccess returns true for 'OK' (case insensitive)")
    func sessionLoginOkCaseInsensitive() throws {
        let json = #"{"status": "OK"}"#
        let resp = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(json.utf8))
        #expect(resp.isSuccess == true)
    }

    @Test("SessionLoginResponse isSuccess returns true for 'ok' via status field")
    func sessionLoginOkViaStatus() throws {
        let json = #"{"status": "ok"}"#
        let resp = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(json.utf8))
        #expect(resp.isSuccess == true)
    }

    @Test("SessionLoginResponse isSuccess returns false for non-ok stat")
    func sessionLoginFail() throws {
        let json = #"{"stat": "fail"}"#
        let resp = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(json.utf8))
        #expect(resp.isSuccess == false)
    }

    @Test("SessionLoginResponse isSuccess returns false when both nil")
    func sessionLoginBothNil() throws {
        let json = "{}"
        let resp = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(json.utf8))
        #expect(resp.isSuccess == false)
    }
}
