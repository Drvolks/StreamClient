//
//  EnvironmentSettingsTests.swift
//  NexusPVRTests
//
//  Tests for EnvironmentSettings (#112) — Dispatcharr
//  `GET /api/core/settings/env/` response model.
//
//  The real fixture was captured against Dispatcharr `core/api_views.py`
//  (the `environment` view). The same shape is what the Dispatcharr
//  web UI consumes in `frontend/src/components/Sidebar.jsx`.
//
//  All test fixture values use RFC 5737 documentation IPs
//  (192.0.2.x / 198.51.100.x / 203.0.113.x) and clearly-fake city /
//  country names. None of the test data is a real user IP, server,
//  or location.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct EnvironmentSettingsTests {

    // MARK: - Decode

    @Test("EnvironmentSettings decodes the canonical Dispatcharr payload")
    func decodesCanonicalPayload() throws {
        let json = #"""
        {
          "authenticated": true,
          "public_ip": "203.0.113.42",
          "local_ip": "192.0.2.10",
          "country_code": "US",
          "country_name": "Exampleland",
          "city": "Test City",
          "ip_lookup_enabled": true,
          "ip_lookup_env_disabled": false,
          "ip_lookup_pending": false,
          "env_mode": "aio",
          "redis_tls": { "enabled": true, "verify": true, "mtls": false },
          "postgres_tls": { "enabled": false, "verify": false, "mtls": false }
        }
        """#
        let env = try JSONDecoder().decode(EnvironmentSettings.self, from: Data(json.utf8))
        #expect(env.publicIP == "203.0.113.42")
        #expect(env.localIP == "192.0.2.10")
        #expect(env.countryCode == "US")
        #expect(env.countryName == "Exampleland")
        #expect(env.city == "Test City")
        #expect(env.ipLookupEnabled == true)
        #expect(env.ipLookupPending == false)
        #expect(env.envMode == "aio")
        #expect(env.redisTLS?.enabled == true)
        #expect(env.redisTLS?.verify == true)
        #expect(env.redisTLS?.mtls == false)
        #expect(env.postgresTLS?.enabled == false)
    }

    @Test("EnvironmentSettings decodes the pending-lookup shape (cache empty)")
    func decodesPendingLookup() throws {
        // Dispatcharr returns this shape on a fresh install: the cache
        // hasn't been populated yet, so the lookup is in flight.
        let json = #"""
        {
          "authenticated": true,
          "public_ip": null,
          "local_ip": null,
          "country_code": null,
          "country_name": null,
          "city": null,
          "ip_lookup_enabled": true,
          "ip_lookup_env_disabled": false,
          "ip_lookup_pending": true,
          "env_mode": "aio"
        }
        """#
        let env = try JSONDecoder().decode(EnvironmentSettings.self, from: Data(json.utf8))
        #expect(env.publicIP == nil)
        #expect(env.countryName == nil)
        #expect(env.ipLookupPending == true)
        #expect(env.ipLookupEnabled == true)
    }

    @Test("EnvironmentSettings decodes the disabled-lookup shape (env var override)")
    func decodesDisabledLookup() throws {
        // Dispatcharr's ENABLE_IP_LOOKUP=False path. The web UI shows
        // a "lookup disabled" placeholder; the client should mirror.
        let json = #"""
        {
          "authenticated": true,
          "public_ip": null,
          "local_ip": null,
          "country_code": null,
          "country_name": null,
          "city": null,
          "ip_lookup_enabled": false,
          "ip_lookup_env_disabled": true,
          "ip_lookup_pending": false,
          "env_mode": "aio"
        }
        """#
        let env = try JSONDecoder().decode(EnvironmentSettings.self, from: Data(json.utf8))
        #expect(env.ipLookupEnabled == false)
        #expect(env.ipLookupPending == false)
    }

    @Test("EnvironmentSettings tolerates missing optional TLS sub-objects")
    func decodesWithoutTLSObjects() throws {
        // Forward-compat: a future Dispatcharr build that drops the
        // redis_tls / postgres_tls sub-objects should still decode.
        let json = #"""
        {
          "authenticated": true,
          "public_ip": "198.51.100.7",
          "ip_lookup_enabled": true,
          "ip_lookup_pending": false,
          "env_mode": "core"
        }
        """#
        let env = try JSONDecoder().decode(EnvironmentSettings.self, from: Data(json.utf8))
        #expect(env.publicIP == "198.51.100.7")
        #expect(env.redisTLS == nil)
        #expect(env.postgresTLS == nil)
        #expect(env.envMode == "core")
    }

    @Test("EnvironmentSettings round-trips via Codable")
    func codableRoundTrip() throws {
        let original = EnvironmentSettings(
            publicIP: "203.0.113.42",
            localIP: "192.0.2.10",
            countryCode: "US",
            countryName: "Exampleland",
            city: "Test City",
            ipLookupEnabled: true,
            ipLookupPending: false,
            envMode: "aio",
            redisTLS: TLSState(enabled: true, verify: true, mtls: false),
            postgresTLS: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EnvironmentSettings.self, from: data)
        #expect(decoded == original)
    }

    @Test("EnvironmentSettings JSON shape pins public_ip snake_case (issue #112 contract)")
    func wireFormatPinsSnakeCase() throws {
        // The Dispatcharr server emits snake_case. Pin the wire format
        // explicitly so a future rename to camelCase on either side
        // is caught at PR-review time, not by a confused user.
        let json = #"{"public_ip": "203.0.113.1", "local_ip": "192.0.2.1", "country_code": "US", "country_name": "Exampleland", "city": "Test City", "ip_lookup_enabled": true, "ip_lookup_pending": false, "env_mode": "aio"}"#
        let decoded = try JSONDecoder().decode(EnvironmentSettings.self, from: Data(json.utf8))
        #expect(decoded.publicIP == "203.0.113.1")
        #expect(decoded.countryCode == "US")

        // Encoded output also uses snake_case so the round-trip is
        // stable and doesn't surprise a future server-side consumer.
        let encoded = String(data: try JSONEncoder().encode(decoded), encoding: .utf8)!
        #expect(encoded.contains("\"public_ip\""))
        #expect(encoded.contains("\"local_ip\""))
        #expect(encoded.contains("\"country_code\""))
        #expect(encoded.contains("\"ip_lookup_enabled\""))
    }

    @Test("EnvironmentSettings decoding does not require 'authenticated' key")
    func decodesWithoutAuthenticated() throws {
        // The server always emits `authenticated: true` because the
        // endpoint is behind `IsAuthenticated`. The `authenticated`
        // field is therefore redundant client-side and the model
        // intentionally does not decode it — but make sure its
        // presence does not break decoding either.
        let json = #"""
        {
          "public_ip": "203.0.113.99",
          "ip_lookup_enabled": true,
          "ip_lookup_pending": false,
          "env_mode": "aio"
        }
        """#
        let env = try JSONDecoder().decode(EnvironmentSettings.self, from: Data(json.utf8))
        #expect(env.publicIP == "203.0.113.99")
    }

    // MARK: - Pending-lookup polling (#112)

    #if DISPATCHERPVR
    /// Dispatcharr resolves the public IP lazily: the first request to
    /// `/api/core/settings/env/` returns `ip_lookup_pending: true` and starts a
    /// background thread. `isEnvironmentLookupPending` is what makes the client
    /// re-poll quickly instead of waiting a full steady-state interval.
    @Test("Pending payloads ask for a fast re-poll")
    func pendingPayloadIsPending() {
        let pending = EnvironmentSettings(
            publicIP: nil, localIP: "192.0.2.10", countryCode: nil,
            countryName: nil, city: nil, ipLookupEnabled: true,
            ipLookupPending: true, envMode: "aio", redisTLS: nil, postgresTLS: nil
        )
        #expect(AppState.isEnvironmentLookupPending(pending))
    }

    @Test("Missing publicIP counts as pending even without the flag")
    func missingPublicIPIsPending() {
        let noIP = EnvironmentSettings(
            publicIP: nil, localIP: "192.0.2.10", countryCode: nil,
            countryName: nil, city: nil, ipLookupEnabled: true,
            ipLookupPending: false, envMode: "aio", redisTLS: nil, postgresTLS: nil
        )
        #expect(AppState.isEnvironmentLookupPending(noIP))
    }

    @Test("Resolved payloads settle to the steady cadence")
    func resolvedPayloadIsNotPending() {
        let resolved = EnvironmentSettings(
            publicIP: "203.0.113.42", localIP: "192.0.2.10", countryCode: "US",
            countryName: "Exampleland", city: "Test City", ipLookupEnabled: true,
            ipLookupPending: false, envMode: "aio", redisTLS: nil, postgresTLS: nil
        )
        #expect(!AppState.isEnvironmentLookupPending(resolved))
    }

    /// A server with lookup disabled never fills the IP in, so fast polling
    /// would just be wasted requests against a permanent placeholder.
    @Test("Lookup disabled never triggers fast polling")
    func lookupDisabledIsNotPending() {
        let disabled = EnvironmentSettings(
            publicIP: nil, localIP: nil, countryCode: nil,
            countryName: nil, city: nil, ipLookupEnabled: false,
            ipLookupPending: false, envMode: "aio", redisTLS: nil, postgresTLS: nil
        )
        #expect(!AppState.isEnvironmentLookupPending(disabled))
    }

    @Test("Fast retries cover the first steady-state interval, then stop")
    func retryScheduleCoversFirstInterval() {
        let delays = AppState.environmentPendingRetryDelays
        #expect(!delays.isEmpty)
        // Each retry is no slower than the steady cadence, and the whole
        // catch-up window is bounded by roughly one steady interval — enough
        // to catch a lookup that takes a few seconds without hammering.
        #expect(delays.allSatisfy { $0 < AppState.environmentRefreshInterval })
        let total = delays.reduce(Duration.zero, +)
        #expect(total <= AppState.environmentRefreshInterval)
    }
    #endif

    // MARK: - AppState integration (#129) — covered by the UI test
    // `testSettingsShowNetworkPanelOnDispatcharr` in NexusPVRUITests
    // (which renders the actual SettingsView with `appState.environmentSettings`).
    // We can't easily unit-test the polling state machine without a mock
    // DispatcherClient, and adding DISPATCHERPVR to the test target
    // would break other tests that use the get-only `userLevel` shape.
}
