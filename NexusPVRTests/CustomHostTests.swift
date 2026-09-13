//
//  CustomHostTests.swift
//  NexusPVRTests
//
//  Custom host routing, validation and persistence (issue #165).
//

import Testing
import Foundation
@testable import NextPVR

private final class FakeNetworkPath: NetworkPathReporting, @unchecked Sendable {
    var prefersReducedData = false
    var isExpensive = false
}

struct CustomHostConfigTests {

    private func config(
        host: String = "http://192.168.1.50:8866",
        customHost: String = "https://pvr.example.com",
        mode: CustomHostMode = .cellularOnly
    ) -> ServerConfig {
        var c = ServerConfig(host: host, pin: "1234", useHTTPS: false)
        c.customHost = customHost
        c.customHostMode = mode
        return c
    }

    // MARK: - Routing

    @Test("Without a custom host the server address is used on every network")
    func noCustomHostUsesServerAddress() {
        let c = config(customHost: "")
        #expect(c.activeBaseURL(onExpensiveNetwork: false) == "http://192.168.1.50:8866")
        #expect(c.activeBaseURL(onExpensiveNetwork: true) == "http://192.168.1.50:8866")
    }

    @Test("A whitespace-only custom host counts as unset")
    func blankCustomHostIsUnset() {
        let c = config(customHost: "   ", mode: .always)
        #expect(!c.hasCustomHost)
        #expect(c.activeBaseURL(onExpensiveNetwork: true) == "http://192.168.1.50:8866")
    }

    @Test("Cellular-only mode uses the custom host only on an expensive network")
    func cellularOnlyMode() {
        let c = config(mode: .cellularOnly)
        #expect(c.activeBaseURL(onExpensiveNetwork: false) == "http://192.168.1.50:8866")
        #expect(c.activeBaseURL(onExpensiveNetwork: true) == "https://pvr.example.com")
    }

    @Test("Always mode uses the custom host on every network")
    func alwaysMode() {
        let c = config(mode: .always)
        #expect(c.activeBaseURL(onExpensiveNetwork: false) == "https://pvr.example.com")
        #expect(c.activeBaseURL(onExpensiveNetwork: true) == "https://pvr.example.com")
    }

    @Test("The custom host is parsed like the server address (port and path)")
    func customHostParsing() {
        let c = config(customHost: "https://pvr.example.com:8443/nextpvr/", mode: .always)
        #expect(c.activeBaseURL(onExpensiveNetwork: false) == "https://pvr.example.com:8443/nextpvr")
    }

    @Test("The server address stays the primary baseURL")
    func baseURLIsUnchanged() {
        #expect(config(mode: .always).baseURL == "http://192.168.1.50:8866")
    }

    // MARK: - Same server

    @Test("Configs differing only in custom host settings are the same server")
    func sameServerIgnoresCustomHost() {
        let a = config(customHost: "", mode: .cellularOnly)
        let b = config(customHost: "https://other.example.com", mode: .always)
        #expect(a.hasSameServer(as: b))
        #expect(a != b)
    }

    @Test("serverIdentity drops only the custom host settings")
    func serverIdentityDropsCustomHost() {
        let c = config(mode: .always)
        let identity = c.serverIdentity
        #expect(identity.customHost == "")
        #expect(identity.customHostMode == .cellularOnly)
        #expect(identity.host == c.host)
        #expect(identity.pin == c.pin)
        // Editing the custom host twice (host, then mode) must not look like a
        // server change to the startup/EPG bootstrap (#165 regression).
        var edited = c
        edited.customHost = "https://other.example.com"
        edited.customHostMode = .cellularOnly
        #expect(edited.serverIdentity == identity)
    }

    @Test("A different server address or credentials is a different server")
    func differentServer() {
        let a = config()
        #expect(!a.hasSameServer(as: config(host: "http://192.168.1.60:8866")))
        var b = a
        b.pin = "9999"
        #expect(!a.hasSameServer(as: b))
    }

    // MARK: - Validation

    @Test("Empty and well-formed custom hosts are accepted", arguments: [
        "", "  ", "https://pvr.example.com", "http://203.0.113.7:8866", "pvr.example.com",
        "pvr.example.com:9191", "https://pvr.example.com/dispatcharr"
    ])
    func validCustomHosts(_ input: String) {
        #expect(ServerConfig.customHostValidationError(input) == nil)
    }

    @Test("Malformed custom hosts are rejected", arguments: [
        "https://", "ftp://pvr.example.com", "pvr example.com", "http:///path",
        "pvr.example.com:", "pvr.example.com:abc", "https://pvr.example.com:70000"
    ])
    func invalidCustomHosts(_ input: String) {
        #expect(ServerConfig.customHostValidationError(input) != nil)
    }

    // MARK: - Persistence

    @Test("Custom host settings survive an encode/decode round trip")
    func roundTrip() throws {
        let original = config(mode: .always)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.customHost == "https://pvr.example.com")
        #expect(decoded.customHostMode == .always)
    }

    @Test("Configs saved before custom hosts existed decode with defaults")
    func legacyDecode() throws {
        let json = #"{"host":"192.168.1.50","port":8866,"pin":"1234","useHTTPS":false}"#
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(decoded.customHost == "")
        #expect(decoded.customHostMode == .cellularOnly)
        #expect(decoded.activeBaseURL(onExpensiveNetwork: true) == "http://192.168.1.50:8866")
    }

    @Test("An unknown mode falls back to the default instead of failing the decode")
    func unknownModeDecode() throws {
        let json = #"{"host":"192.168.1.50","pin":"","useHTTPS":false,"customHost":"https://pvr.example.com","customHostMode":"wifiOnly"}"#
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(decoded.customHost == "https://pvr.example.com")
        #expect(decoded.customHostMode == .cellularOnly)
    }
}

@MainActor
struct CustomHostClientTests {

    private func makeClient(mode: CustomHostMode, path: FakeNetworkPath) -> NextPVRClient {
        var c = ServerConfig(host: "http://192.168.1.50:8866", pin: "1234", useHTTPS: false)
        c.customHost = "https://pvr.example.com"
        c.customHostMode = mode
        return NextPVRClient(config: c, networkPath: path)
    }

    @Test("The client re-evaluates the route on each request as the network changes")
    func clientFollowsNetworkChanges() {
        let path = FakeNetworkPath()
        let client = makeClient(mode: .cellularOnly, path: path)
        #expect(client.baseURL == "http://192.168.1.50:8866")
        path.isExpensive = true
        #expect(client.baseURL == "https://pvr.example.com")
        path.isExpensive = false
        #expect(client.baseURL == "http://192.168.1.50:8866")
    }

    @Test("Low Data Mode alone does not switch to the custom host")
    func lowDataModeKeepsServerAddress() {
        let path = FakeNetworkPath()
        path.prefersReducedData = true
        let client = makeClient(mode: .cellularOnly, path: path)
        #expect(client.baseURL == "http://192.168.1.50:8866")
    }

    @Test("Changing the custom host reroutes without resetting the session state")
    func updateCustomHostKeepsServer() {
        let path = FakeNetworkPath()
        let client = makeClient(mode: .cellularOnly, path: path)
        let before = client.config
        client.updateCustomHost("https://new.example.com", mode: .always)
        #expect(client.baseURL == "https://new.example.com")
        #expect(client.config.hasSameServer(as: before))
        client.updateCustomHost("", mode: .always)
        #expect(client.baseURL == "http://192.168.1.50:8866")
    }
}
