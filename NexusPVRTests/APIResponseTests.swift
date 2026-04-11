//
//  APIResponseTests.swift
//  NexusPVRTests
//
//  Tests for the simple NextPVR JSON response wrappers.
//

import Testing
import Foundation
@testable import NextPVR

struct APIResponseTests {

    // MARK: - APIResponse.isSuccess

    @Test("APIResponse isSuccess true when stat == 'ok'")
    func apiSuccessFromStat() throws {
        let json = #"{"stat": "ok"}"#
        let r = try JSONDecoder().decode(APIResponse.self, from: Data(json.utf8))
        #expect(r.isSuccess)
    }

    @Test("APIResponse isSuccess is case-insensitive")
    func apiSuccessCaseInsensitive() throws {
        let json = #"{"stat": "OK"}"#
        let r = try JSONDecoder().decode(APIResponse.self, from: Data(json.utf8))
        #expect(r.isSuccess)
    }

    @Test("APIResponse isSuccess falls back to status field when stat missing")
    func apiSuccessFromStatus() throws {
        let json = #"{"status": "ok"}"#
        let r = try JSONDecoder().decode(APIResponse.self, from: Data(json.utf8))
        #expect(r.isSuccess)
    }

    @Test("APIResponse isSuccess false when both fields missing")
    func apiSuccessEmpty() throws {
        let r = try JSONDecoder().decode(APIResponse.self, from: Data("{}".utf8))
        #expect(r.isSuccess == false)
    }

    @Test("APIResponse isSuccess false for non-ok string")
    func apiSuccessFailure() throws {
        let json = #"{"stat": "error"}"#
        let r = try JSONDecoder().decode(APIResponse.self, from: Data(json.utf8))
        #expect(r.isSuccess == false)
    }

    // MARK: - SessionLoginResponse

    @Test("SessionLoginResponse mirrors APIResponse success logic")
    func loginSuccess() throws {
        let r = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(#"{"stat":"ok"}"#.utf8))
        #expect(r.isSuccess)

        let r2 = try JSONDecoder().decode(SessionLoginResponse.self, from: Data(#"{"status":"OK"}"#.utf8))
        #expect(r2.isSuccess)

        let r3 = try JSONDecoder().decode(SessionLoginResponse.self, from: Data("{}".utf8))
        #expect(r3.isSuccess == false)
    }

    // MARK: - SessionInitiateResponse

    @Test("SessionInitiateResponse decodes sid and salt")
    func initiateDecodes() throws {
        let json = #"{"sid": "session-123", "salt": "abc123", "stat": "ok"}"#
        let r = try JSONDecoder().decode(SessionInitiateResponse.self, from: Data(json.utf8))
        #expect(r.sid == "session-123")
        #expect(r.salt == "abc123")
        #expect(r.stat == "ok")
    }

    @Test("SessionInitiateResponse fields all optional")
    func initiateEmpty() throws {
        let r = try JSONDecoder().decode(SessionInitiateResponse.self, from: Data("{}".utf8))
        #expect(r.sid == nil)
        #expect(r.salt == nil)
        #expect(r.stat == nil)
    }
}
