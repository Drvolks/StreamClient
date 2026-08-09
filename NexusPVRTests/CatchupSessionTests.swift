//
//  CatchupSessionTests.swift
//  NexusPVRTests
//
//  Tests for CatchupSession models and CatchupService URL resolution
//  (#119 — Dispatcharr catch-up / timeshift).
//
//  All test fixtures use the snake_case wire format documented in
//  the pinned spec comment on issue #119, derived from Dispatcharr
//  commit 223dff33 (`apps/timeshift/api_views.py`,
//  `apps/timeshift/sessions.py`).
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct CatchupSessionTests {

    // MARK: - CatchupSessionRequest

    @Test("CatchupSessionRequest encodes channel_uuid / start in snake_case")
    func requestEncodesSnakeCase() throws {
        let req = CatchupSessionRequest(channelUuid: "00000000-0000-0000-0000-000000000001", startISO8601: "2026-07-09T14:00:00Z")
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"channel_uuid\""))
        #expect(json.contains("\"start\""))
        #expect(json.contains("\"00000000-0000-0000-0000-000000000001\""))
        #expect(json.contains("\"2026-07-09T14:00:00Z\""))
        #expect(!json.contains("\"channelUuid\""), "must use server's snake_case, not Swift camelCase")
    }

    @Test("CatchupSessionRequest round-trips via Codable")
    func requestRoundTrip() throws {
        let original = CatchupSessionRequest(channelUuid: "00000000-0000-0000-0000-000000000002", startISO8601: "2026-08-15T19:30:00Z")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CatchupSessionRequest.self, from: data)
        #expect(decoded == original)
    }

    @Test("CatchupSessionRequest decodes a Unix-epoch 'start' if server sends it")
    func requestDecodesUnixEpoch() throws {
        // Dispatcharr's `parse_catchup_timestamp` accepts Unix epoch
        // seconds as well as ISO-8601; the server might echo it
        // back either way. We must not crash on either.
        let json = #"{"channel_uuid": "00000000-0000-0000-0000-000000000003", "start": "1719837600"}"#
        let decoded = try JSONDecoder().decode(CatchupSessionRequest.self, from: Data(json.utf8))
        #expect(decoded.channelUuid == "00000000-0000-0000-0000-000000000003")
        #expect(decoded.start == "1719837600")
    }

    // MARK: - CatchupSessionCreateResponse

    @Test("CatchupSessionCreateResponse decodes the canonical POST /sessions/ payload")
    func responseDecodesCanonical() throws {
        let json = #"""
        {
          "session_id": "opaque-token-00000000",
          "playback_url": "/proxy/catchup/00000000-0000-0000-0000-000000000004?session_id=opaque-token-00000000",
          "expires_at": 1719837660,
          "channel_uuid": "00000000-0000-0000-0000-000000000004",
          "start": "2026-07-09T14:00:00Z"
        }
        """#
        let resp = try JSONDecoder().decode(CatchupSessionCreateResponse.self, from: Data(json.utf8))
        #expect(resp.sessionId == "opaque-token-00000000")
        #expect(resp.playbackUrl == "/proxy/catchup/00000000-0000-0000-0000-000000000004?session_id=opaque-token-00000000")
        #expect(resp.expiresAt == 1719837660)
        #expect(resp.channelUuid == "00000000-0000-0000-0000-000000000004")
        #expect(resp.start == "2026-07-09T14:00:00Z")
    }

    @Test("CatchupSessionCreateResponse round-trips via Codable")
    func responseRoundTrip() throws {
        let original = CatchupSessionCreateResponse(
            sessionId: "opaque-token-aaaa",
            playbackUrl: "/proxy/catchup/00000000-0000-0000-0000-0000000000aa?session_id=opaque-token-aaaa",
            expiresAt: 1719837660,
            channelUuid: "00000000-0000-0000-0000-0000000000aa",
            start: "2026-07-09T14:00:00Z"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CatchupSessionCreateResponse.self, from: data)
        #expect(decoded == original)
    }

    @Test("CatchupSessionCreateResponse snake_case wire format pin")
    func responseWireFormatPinsSnakeCase() throws {
        // Issue #119 contract: server emits snake_case. Pin the wire
        // format explicitly so a future rename is caught at PR-review
        // time, not by a confused user with a broken session.
        let json = #"{"session_id": "x", "playback_url": "/y", "expires_at": 1, "channel_uuid": "z", "start": "t"}"#
        let decoded = try JSONDecoder().decode(CatchupSessionCreateResponse.self, from: Data(json.utf8))
        #expect(decoded.sessionId == "x")
        #expect(decoded.playbackUrl == "/y")
        #expect(decoded.expiresAt == 1)
        #expect(decoded.channelUuid == "z")
        #expect(decoded.start == "t")

        let encoded = String(data: try JSONEncoder().encode(decoded), encoding: .utf8)!
        #expect(encoded.contains("\"session_id\""))
        #expect(encoded.contains("\"playback_url\""))
        #expect(encoded.contains("\"expires_at\""))
        #expect(encoded.contains("\"channel_uuid\""))
        #expect(!encoded.contains("\"sessionId\""), "must encode snake_case to match server")
    }

    @Test("CatchupSessionCreateResponse does not decode an unknown 'reason' field")
    func responseIgnoresUnknownFields() throws {
        // Forward-compat: if Dispatcharr adds a new field to the
        // POST response (e.g. a server-side `metadata` object for
        // EPG enrichment), the model should decode cleanly without
        // a schema bump.
        let json = #"""
        {
          "session_id": "x",
          "playback_url": "/y",
          "expires_at": 1,
          "channel_uuid": "z",
          "start": "t",
          "future_field_we_dont_know_about": { "foo": "bar" },
          "another_new_field": [1, 2, 3]
        }
        """#
        let decoded = try JSONDecoder().decode(CatchupSessionCreateResponse.self, from: Data(json.utf8))
        #expect(decoded.sessionId == "x")
        #expect(decoded.expiresAt == 1)
    }

    // MARK: - TTL constants

    @Test("CatchupService TTL constants match the spec (60s handshake, 600s idle)")
    func ttlConstantsMatchSpec() {
        // Pinned regression test for issue #119 comment §2. If
        // Dispatcharr changes either TTL, both this constant and
        // the corresponding Dispatcharr line must change in lock
        // step. The pin makes the cross-reference explicit at
        // review time.
        #expect(CatchupService.handshakeTTLSeconds == 60)
        #expect(CatchupService.idleTTLSeconds == 600)
    }
}