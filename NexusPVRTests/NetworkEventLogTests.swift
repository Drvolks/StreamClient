//
//  NetworkEventLogTests.swift
//  NexusPVRTests
//
//  Tests for NetworkEventLog.consoleLine formatting.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct NetworkEventLogTests {

    private func event(
        method: String = "GET",
        path: String = "/api/test",
        statusCode: Int? = 200,
        isSuccess: Bool = true,
        durationMs: Int = 100,
        responseSize: Int = 512,
        errorDetail: String? = nil
    ) -> NetworkEvent {
        NetworkEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            method: method,
            path: path,
            statusCode: statusCode,
            isSuccess: isSuccess,
            durationMs: durationMs,
            responseSize: responseSize,
            errorDetail: errorDetail
        )
    }

    @Test("Console line includes method, path, status code, and duration")
    func basicLine() {
        let line = NetworkEventLog.consoleLine(for: event())
        #expect(line.contains("GET"))
        #expect(line.contains("/api/test"))
        #expect(line.contains("→ 200"))
        #expect(line.contains("(100ms)"))
    }

    @Test("Missing status code shows no arrow for successful request")
    func missingStatusOnSuccess() {
        let line = NetworkEventLog.consoleLine(for: event(statusCode: nil, isSuccess: true))
        #expect(line.contains("→") == false)
    }

    @Test("Missing status code on failed request shows → ERR")
    func missingStatusOnFailure() {
        let line = NetworkEventLog.consoleLine(for: event(statusCode: nil, isSuccess: false))
        #expect(line.contains("→ ERR"))
    }

    @Test("Zero duration omits the duration suffix")
    func zeroDuration() {
        let line = NetworkEventLog.consoleLine(for: event(durationMs: 0))
        #expect(line.contains("ms)") == false)
    }

    @Test("Error detail is appended on a new indented line")
    func errorDetailAppended() {
        let line = NetworkEventLog.consoleLine(for: event(errorDetail: "Connection reset"))
        #expect(line.contains("\n  Connection reset"))
    }

    @Test("POST method is rendered verbatim")
    func postMethod() {
        let line = NetworkEventLog.consoleLine(for: event(method: "POST"))
        #expect(line.contains("POST /api/test"))
    }

    @Test("Status code arrow uses decimal value for 4xx responses")
    func fourOhFour() {
        let line = NetworkEventLog.consoleLine(for: event(statusCode: 404, isSuccess: false))
        #expect(line.contains("→ 404"))
    }

    @Test("NetworkEvent id is unique per instance")
    func uniqueIds() {
        let a = event()
        let b = event()
        #expect(a.id != b.id)
    }
}
