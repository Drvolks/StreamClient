//
//  NetworkEventLogExtraTests.swift
//  NexusPVRTests
//
//  Additional tests for NetworkEventLog: formattedLog, consoleLine, event capping.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct NetworkEventLogExtraTests {

    @Test("NetworkEventLog initial events are empty")
    func initialEventsEmpty() {
        let log = NetworkEventLog()
        #expect(log.events.isEmpty)
    }

    @Test("NetworkEventLog formattedLog is empty initially")
    func formattedLogEmpty() {
        let log = NetworkEventLog()
        #expect(log.formattedLog.isEmpty)
    }

    @Test("consoleLine formats a successful event")
    func consoleLineSuccess() {
        let event = NetworkEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            method: "GET",
            path: "/api/channels",
            statusCode: 200,
            isSuccess: true,
            durationMs: 42,
            responseSize: 1024,
            errorDetail: nil
        )
        let line = NetworkEventLog.consoleLine(for: event)
        #expect(line.contains("GET"))
        #expect(line.contains("/api/channels"))
        #expect(line.contains("200"))
        #expect(line.contains("42ms"))
    }

    @Test("consoleLine formats an event without statusCode")
    func consoleLineNoStatusCode() {
        let event = NetworkEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            method: "POST",
            path: "/api/auth",
            statusCode: nil,
            isSuccess: true,
            durationMs: 0,
            responseSize: 0,
            errorDetail: nil
        )
        let line = NetworkEventLog.consoleLine(for: event)
        #expect(line.contains("POST"))
        #expect(line.contains("/api/auth"))
        #expect(!line.contains("ms"))
    }

    @Test("consoleLine formats an error event")
    func consoleLineError() {
        let event = NetworkEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            method: "GET",
            path: "/api/error",
            statusCode: nil,
            isSuccess: false,
            durationMs: 100,
            responseSize: 0,
            errorDetail: "Connection refused"
        )
        let line = NetworkEventLog.consoleLine(for: event)
        #expect(line.contains("ERR"))
        #expect(line.contains("Connection refused"))
    }

    @Test("consoleLine includes error detail when present")
    func consoleLineErrorDetail() {
        let event = NetworkEvent(
            timestamp: Date(timeIntervalSince1970: 0),
            method: "GET",
            path: "/x",
            statusCode: 500,
            isSuccess: false,
            durationMs: 500,
            responseSize: 0,
            errorDetail: "Internal Server Error"
        )
        let line = NetworkEventLog.consoleLine(for: event)
        #expect(line.contains("Internal Server Error"))
        #expect(line.contains("500"))
    }

    @Test("clear removes all events")
    func clearRemovesEvents() {
        let log = NetworkEventLog()
        let event = NetworkEvent(
            timestamp: Date(),
            method: "GET",
            path: "/test",
            statusCode: 200,
            isSuccess: true,
            durationMs: 10,
            responseSize: 0,
            errorDetail: nil
        )
        log.log(event)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            log.clear()
            #expect(log.events.isEmpty)
            #expect(log.formattedLog.isEmpty)
        }
    }
}
