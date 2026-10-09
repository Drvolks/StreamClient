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
    private let lock = NSLock()
    private var reduced = false
    private var expensive = false
    private var ssid: String?
    var prefersReducedData: Bool {
        get { lock.withLock { reduced } }
        set { lock.withLock { reduced = newValue } }
    }
    var isExpensive: Bool {
        get { lock.withLock { expensive } }
        set { lock.withLock { expensive = newValue } }
    }
    var currentWiFiSSID: String? {
        get { lock.withLock { ssid } }
        set { lock.withLock { ssid = newValue } }
    }
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


struct WiFiCustomHostConfigTests {
    private func config(ssid: String = "My Home Wi-Fi") -> ServerConfig {
        var config = ServerConfig(host: "http://192.168.1.50:8866", pin: "1234", useHTTPS: false)
        config.customHost = "https://pvr.example.com"
        config.customHostMode = .outsideWiFiNetwork
        config.customHostWiFiSSID = ssid
        return config
    }

    @Test("Only an exact SSID match uses the primary address", arguments: [
        "My Home Wi-Fi", "my home wi-fi", " My Home Wi-Fi", "My Home Wi-Fi ", "Other Wi-Fi", ""
    ])
    func matching(ssid: String) {
        let config = config()
        #if os(tvOS)
        let expected = config.baseURL
        #else
        let expected = ssid == "My Home Wi-Fi" ? config.baseURL : "https://pvr.example.com"
        #endif
        // Cost never changes the SSID decision (including a matching hotspot).
        for expensive in [false, true] {
            #expect(config.activeBaseURL(onExpensiveNetwork: expensive, currentWiFiSSID: ssid) == expected)
        }
    }

    @Test("Unknown networks and unset SSIDs fall back to the custom host")
    func unavailableSSID() {
        let configured = config()
        let empty = config(ssid: "")
        #if os(tvOS)
        #expect(configured.activeBaseURL(onExpensiveNetwork: false) == configured.baseURL)
        #expect(empty.activeBaseURL(onExpensiveNetwork: false, currentWiFiSSID: "My Home Wi-Fi") == empty.baseURL)
        #else
        #expect(configured.activeBaseURL(onExpensiveNetwork: false) == "https://pvr.example.com")
        #expect(empty.activeBaseURL(onExpensiveNetwork: false, currentWiFiSSID: "My Home Wi-Fi") == "https://pvr.example.com")
        #endif
        var noCustomHost = configured
        noCustomHost.customHost = ""
        #expect(noCustomHost.activeBaseURL(onExpensiveNetwork: true) == noCustomHost.baseURL)
    }

    @Test("SSID comparison does not normalize Unicode or strip whitespace")
    func exactBytes() {
        let config = config(ssid: " Café ")
        #expect(config.usesCustomHost(onExpensiveNetwork: false, currentWiFiSSID: " Café ") == false)
        #if !os(tvOS)
        #expect(config.usesCustomHost(onExpensiveNetwork: false, currentWiFiSSID: " Café") == true)
        #expect(config.usesCustomHost(onExpensiveNetwork: false, currentWiFiSSID: " Cafe\u{301} ") == true)
        #endif
    }

    @Test("Wi-Fi settings persist locally and do not change server identity")
    func localRoundTrip() throws {
        let original = config()
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.customHostWiFiSSID == "My Home Wi-Fi")
        #expect(original.hasSameServer(as: config(ssid: "Another Wi-Fi")))
        #expect(original.serverIdentity.customHostWiFiSSID.isEmpty)
    }

    @Test("Cloud sync omits SSIDs and restores only this device's matching server preference")
    func cloudSync() throws {
        let local = config()
        let synced = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(local.cloudSyncedConfig))
        #expect(synced.customHostWiFiSSID.isEmpty)
        #expect(synced.customHostMode == .outsideWiFiNetwork)
        #expect(synced.restoringDeviceRouting(from: local).customHostWiFiSSID == "My Home Wi-Fi")
        #expect(synced.restoringDeviceRouting(from: nil).customHostWiFiSSID.isEmpty)
        var otherServer = local
        otherServer.host = "other.example.com"
        #expect(synced.restoringDeviceRouting(from: otherServer).customHostWiFiSSID.isEmpty)
    }

    @Test("Absolute server-owned recording/artwork URLs follow the selected route")
    func absoluteServerURLs() throws {
        var config = config()
        config.host = "http://192.168.1.50:8866/pvr"
        config.customHost = "https://pvr.example.com/remote"
        let customBaseURL = try #require(config.customHostBaseURL)
        let local = try #require(URL(string: "http://192.168.1.50:8866/pvr/recordings/42?token=secret#video"))
        let remote = try #require(URL(string: "https://pvr.example.com:443/remote/recordings/42?token=secret#video"))
        #if os(tvOS)
        #expect(config.routedServerURL(local, activeBaseURL: customBaseURL) == local)
        #else
        #expect(config.routedServerURL(local, activeBaseURL: customBaseURL).absoluteString
            == "https://pvr.example.com/remote/recordings/42?token=secret#video")
        #expect(config.routedServerURL(remote, activeBaseURL: config.baseURL).absoluteString
            == "http://192.168.1.50:8866/pvr/recordings/42?token=secret#video")
        #endif
        for string in ["https://cdn.example.com/artwork.png", "https://pvr.example.com/remote-other/artwork.png"] {
            let external = try #require(URL(string: string))
            #expect(config.routedServerURL(external, activeBaseURL: config.baseURL) == external)
        }
    }

    @Test("Existing custom host configurations decode without an SSID", arguments: ["cellularOnly", "always"])
    func legacyCustomHost(mode: String) throws {
        let json = """
        {"host":"192.168.1.50","pin":"1234","useHTTPS":false,"customHost":"https://pvr.example.com","customHostMode":"\(mode)"}
        """
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(decoded.customHostWiFiSSID.isEmpty)
        #expect(decoded.customHostMode.rawValue == mode)
    }
}

@MainActor
struct WiFiCustomHostClientTests {
    @Test("Both clients re-evaluate Wi-Fi routing and previously returned URLs stay unchanged")
    func networkTransitions() throws {
        var config = ServerConfig(host: "http://192.168.1.50:8866", pin: "1234", useHTTPS: false)
        config.customHost = "https://pvr.example.com"
        config.customHostMode = .outsideWiFiNetwork
        config.customHostWiFiSSID = "Home"
        let path = FakeNetworkPath()
        let nextPVR = NextPVRClient(config: config, networkPath: path)
        let dispatcharr = DispatcherClient(config: config, networkPath: path)
        path.currentWiFiSSID = "Home"
        #expect(nextPVR.baseURL == config.baseURL)
        #expect(dispatcharr.baseURL == config.baseURL)
        let existingArtwork = try #require(nextPVR.recordingArtworkURL(recordingId: 42, fanart: false))
        for ssid in ["Other", nil, "Home"] as [String?] {
            path.currentWiFiSSID = ssid
            #if os(tvOS)
            let expected = config.baseURL
            #else
            let expected = ssid == "Home" ? config.baseURL : "https://pvr.example.com"
            #endif
            #expect(nextPVR.baseURL == expected)
            #expect(dispatcharr.baseURL == expected)
            #expect(existingArtwork.host == "192.168.1.50")
            #expect(nextPVR.recordingArtworkURL(recordingId: 42, fanart: true)?.host == URL(string: expected)?.host)
        }
        nextPVR.updateCustomHost(config.customHost, mode: .outsideWiFiNetwork, wiFiSSID: "Other")
        dispatcharr.updateCustomHost(config.customHost, mode: .outsideWiFiNetwork, wiFiSSID: "Other")
        #expect(nextPVR.config.hasSameServer(as: config))
        #expect(dispatcharr.config.hasSameServer(as: config))
        #expect(nextPVR.config.customHostWiFiSSID == "Other")
        #expect(dispatcharr.config.customHostWiFiSSID == "Other")
        #if !os(tvOS)
        #expect(nextPVR.baseURL == "https://pvr.example.com")
        #expect(dispatcharr.baseURL == "https://pvr.example.com")
        #endif
    }
}
