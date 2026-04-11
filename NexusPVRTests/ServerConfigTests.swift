//
//  ServerConfigTests.swift
//  NexusPVRTests
//
//  Tests for ServerConfig URL parsing and computed properties.
//

import Testing
import Foundation
@testable import NextPVR

struct ServerConfigTests {

    // MARK: - Helpers

    private func config(
        host: String,
        port: Int? = nil,
        useHTTPS: Bool = false,
        username: String = "",
        password: String = "",
        apiKey: String = ""
    ) -> ServerConfig {
        ServerConfig(
            host: host,
            port: port,
            pin: "",
            username: username,
            password: password,
            apiKey: apiKey,
            useHTTPS: useHTTPS
        )
    }

    // MARK: - baseURL

    @Test("baseURL uses http when useHTTPS is false")
    func baseURL_defaultsHTTPWhenNoScheme() {
        let c = config(host: "example.com", useHTTPS: false)
        #expect(c.baseURL == "http://example.com")
    }

    @Test("baseURL uses https when useHTTPS is true")
    func baseURL_usesHTTPSFromFlag() {
        let c = config(host: "example.com", useHTTPS: true)
        #expect(c.baseURL == "https://example.com")
    }

    @Test("baseURL appends explicit non-default port")
    func baseURL_appendsExplicitPort() {
        let c = config(host: "example.com", port: 9191, useHTTPS: false)
        #expect(c.baseURL == "http://example.com:9191")
    }

    @Test("baseURL omits port when it equals scheme default")
    func baseURL_omitsDefaultPort() {
        let http = config(host: "example.com", port: 80, useHTTPS: false)
        let https = config(host: "example.com", port: 443, useHTTPS: true)
        #expect(http.baseURL == "http://example.com")
        #expect(https.baseURL == "https://example.com")
    }

    @Test("baseURL extracts embedded port from host")
    func baseURL_extractsEmbeddedPort() {
        let c = config(host: "example.com:9191", useHTTPS: false)
        #expect(c.baseURL == "http://example.com:9191")
    }

    @Test("baseURL preserves explicit https scheme in host over useHTTPS flag")
    func baseURL_explicitSchemeWinsOverFlag() {
        let c = config(host: "https://example.com", useHTTPS: false)
        #expect(c.baseURL == "https://example.com")
    }

    @Test("baseURL preserves explicit http scheme in host over useHTTPS flag")
    func baseURL_explicitHTTPSchemeWins() {
        let c = config(host: "http://example.com", useHTTPS: true)
        #expect(c.baseURL == "http://example.com")
    }

    @Test("baseURL strips trailing slash")
    func baseURL_stripsTrailingSlash() {
        let c = config(host: "example.com/", useHTTPS: false)
        #expect(c.baseURL == "http://example.com")
    }

    @Test("baseURL trims leading and trailing whitespace")
    func baseURL_trimsWhitespace() {
        let c = config(host: "  example.com  ", useHTTPS: false)
        #expect(c.baseURL == "http://example.com")
    }

    @Test("baseURL preserves path component")
    func baseURL_includesPath() {
        let c = config(host: "example.com/api/v1", useHTTPS: false)
        #expect(c.baseURL == "http://example.com/api/v1")
    }

    @Test("baseURL combines scheme, embedded port, and path")
    func baseURL_combinesEverything() {
        let c = config(host: "https://example.com:8443/api", useHTTPS: false)
        #expect(c.baseURL == "https://example.com:8443/api")
    }

    @Test("baseURL percent-encodes spaces in host")
    func baseURL_percentEncodesHost() {
        let c = config(host: "my server", useHTTPS: false)
        // " " → "%20"
        #expect(c.baseURL.contains("%20"))
    }

    // MARK: - explicitHostPort

    @Test("explicitHostPort returns numeric port from host")
    func explicitHostPort_parsesSimple() {
        #expect(config(host: "myserver:9191").explicitHostPort == 9191)
    }

    @Test("explicitHostPort strips scheme prefix before parsing")
    func explicitHostPort_stripsScheme() {
        #expect(config(host: "http://myserver:9191").explicitHostPort == 9191)
        #expect(config(host: "https://myserver:9191").explicitHostPort == 9191)
    }

    @Test("explicitHostPort returns nil when no colon")
    func explicitHostPort_nilWhenNoColon() {
        #expect(config(host: "myserver").explicitHostPort == nil)
    }

    @Test("explicitHostPort returns nil for non-numeric port")
    func explicitHostPort_nilForNonNumeric() {
        #expect(config(host: "myserver:abc").explicitHostPort == nil)
    }

    @Test("explicitHostPort ignores colons in path")
    func explicitHostPort_ignoresPathColons() {
        #expect(config(host: "myserver/path:80").explicitHostPort == nil)
    }

    // MARK: - hasExplicitScheme / hasExplicitPort

    @Test("hasExplicitScheme detects http and https, case-insensitive")
    func hasExplicitScheme_variants() {
        #expect(config(host: "http://example.com").hasExplicitScheme)
        #expect(config(host: "https://example.com").hasExplicitScheme)
        #expect(config(host: "HTTPS://example.com").hasExplicitScheme)
        #expect(config(host: "example.com").hasExplicitScheme == false)
    }

    @Test("hasExplicitPort detects numeric port in host field")
    func hasExplicitPort_detects() {
        #expect(config(host: "example.com:9191").hasExplicitPort)
        #expect(config(host: "https://example.com:9191/path").hasExplicitPort)
        #expect(config(host: "example.com").hasExplicitPort == false)
        #expect(config(host: "example.com:abc").hasExplicitPort == false)
    }

    // MARK: - editableURL

    @Test("editableURL returns empty string for empty host")
    func editableURL_emptyHost() {
        #expect(config(host: "").editableURL == "")
    }

    @Test("editableURL returns host as-is when scheme is present")
    func editableURL_schemePassThrough() {
        let c = config(host: "http://example.com", useHTTPS: true)
        #expect(c.editableURL == "http://example.com")
    }

    @Test("editableURL folds scheme and non-default port into host")
    func editableURL_foldsSchemeAndPort() {
        let c = config(host: "example.com", port: 8080, useHTTPS: false)
        #expect(c.editableURL == "http://example.com:8080")
    }

    @Test("editableURL omits default port for scheme")
    func editableURL_omitsDefaultPort() {
        let http = config(host: "example.com", port: 80, useHTTPS: false)
        let https = config(host: "example.com", port: 443, useHTTPS: true)
        #expect(http.editableURL == "http://example.com")
        #expect(https.editableURL == "https://example.com")
    }

    // MARK: - isDemoMode / isConfigured

    @Test("isDemoMode detects host = demo (case-insensitive)")
    func isDemoMode_host() {
        #expect(config(host: "demo").isDemoMode)
        #expect(config(host: "DEMO").isDemoMode)
    }

    @Test("isDemoMode detects demo credentials")
    func isDemoMode_credentials() {
        #expect(config(host: "example.com", username: "demo", password: "demo").isDemoMode)
        #expect(config(host: "example.com", apiKey: "demo").isDemoMode)
    }

    @Test("isDemoMode is false for normal configuration")
    func isDemoMode_normal() {
        let c = config(host: "example.com", username: "user", password: "pass")
        #expect(c.isDemoMode == false)
    }

    @Test("isConfigured true when host is set")
    func isConfigured_withHost() {
        #expect(config(host: "example.com").isConfigured)
    }

    @Test("isConfigured true for demo mode even with empty host")
    func isConfigured_demoEmptyHost() {
        #expect(config(host: "", username: "demo", password: "demo").isConfigured)
    }

    @Test("isConfigured false for blank config")
    func isConfigured_blank() {
        #expect(config(host: "").isConfigured == false)
    }

    // MARK: - effectivePort

    @Test("effectivePort returns explicit port when set")
    func effectivePort_explicit() {
        #expect(config(host: "x", port: 9191).effectivePort == 9191)
    }

    @Test("effectivePort defaults to 80 for http, 443 for https")
    func effectivePort_defaults() {
        #expect(config(host: "x", useHTTPS: false).effectivePort == 80)
        #expect(config(host: "x", useHTTPS: true).effectivePort == 443)
    }

    // MARK: - Codable round-trip

    @Test("ServerConfig encode/decode preserves fields")
    func codable_roundTrip() throws {
        let original = ServerConfig(
            host: "example.com",
            port: 9191,
            pin: "1234",
            username: "admin",
            password: "secret",
            apiKey: "abc",
            useHTTPS: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("ServerConfig decode treats port 0 as nil")
    func codable_portZeroBecomesNil() throws {
        let json = #"{"host":"example.com","port":0,"pin":"","username":"","password":"","apiKey":"","useHTTPS":false}"#
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(decoded.port == nil)
    }

    @Test("ServerConfig decode defaults pin/username/password/apiKey to empty strings when missing")
    func codable_optionalStringDefaults() throws {
        // Only host and useHTTPS are required; everything else should default.
        let json = #"{"host":"example.com","useHTTPS":true}"#
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(decoded.pin == "")
        #expect(decoded.username == "")
        #expect(decoded.password == "")
        #expect(decoded.apiKey == "")
        #expect(decoded.port == nil)
    }

    @Test("ServerConfig decode defaults only pin when pin is missing")
    func codable_missingPinOnly() throws {
        let json = #"{"host":"x","username":"u","password":"p","apiKey":"k","useHTTPS":false}"#
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(decoded.pin == "")
        #expect(decoded.username == "u")
        #expect(decoded.password == "p")
        #expect(decoded.apiKey == "k")
    }

    // MARK: - displayAddress

    @Test("displayAddress includes the port when one is set")
    func displayAddress_withPort() {
        let c = config(host: "192.168.1.100", port: 8866)
        #expect(c.displayAddress == "192.168.1.100:8866")
    }

    @Test("displayAddress is just the host when port is nil")
    func displayAddress_withoutPort() {
        let c = config(host: "example.com")
        #expect(c.displayAddress == "example.com")
    }
}
