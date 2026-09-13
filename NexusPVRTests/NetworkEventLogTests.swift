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

    // MARK: - Host (#165)

    @Test("Console line shows the host between method and path")
    func lineIncludesHost() {
        var e = event()
        e.host = "pvr.example.com"
        let line = NetworkEventLog.consoleLine(for: e)
        #expect(line.contains("GET [pvr.example.com] /api/test"))
    }

    @Test("Console line omits the host brackets when no host is known")
    func lineWithoutHost() {
        let line = NetworkEventLog.consoleLine(for: event())
        #expect(!line.contains("["))
    }

    @Test("hostLabel keeps an explicit port and drops scheme and path", arguments: [
        ("http://192.168.1.50:8866/services/service?sid=x", "192.168.1.50:8866"),
        ("https://pvr.example.com/api/channels/", "pvr.example.com"),
        ("https://pvr.example.com:443/", "pvr.example.com:443"),
    ])
    func hostLabel(_ input: String, _ expected: String) {
        #expect(NetworkEvent.hostLabel(for: URL(string: input)) == expected)
    }

    @Test("hostLabel is nil without a URL or host")
    func hostLabelNil() {
        #expect(NetworkEvent.hostLabel(for: nil) == nil)
        #expect(NetworkEvent.hostLabel(for: URL(string: "/relative/path")) == nil)
    }

    @Test("A client tags its events with the host the request went to")
    func clientTagsCustomHost() async throws {
        let log = NetworkEventLog()
        let path = TestNetworkPath()
        path.isExpensive = true
        var config = ServerConfig(host: "http://127.0.0.1:1", pin: "0000", useHTTPS: false)
        config.customHost = "http://127.0.0.2:1"
        config.customHostMode = .cellularOnly
        let client = NextPVRClient(config: config, networkEventLogger: log, networkPath: path)
        // The first events are logged before any network I/O; don't wait for
        // the unreachable connect and its retries.
        let auth = Task { try? await client.authenticate() }
        for _ in 0..<200 where log.events.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        auth.cancel()
        let hosts = Set(log.events.compactMap(\.host))
        #expect(hosts.contains("127.0.0.2:1"))
        #expect(!hosts.contains("127.0.0.1:1"))
    }

    @Test("NetworkEvent id is unique per instance")
    func uniqueIds() {
        let a = event()
        let b = event()
        #expect(a.id != b.id)
    }
}

private final class TestNetworkPath: NetworkPathReporting, @unchecked Sendable {
    var prefersReducedData = false
    var isExpensive = false
}
