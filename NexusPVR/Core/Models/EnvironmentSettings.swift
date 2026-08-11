//
//  EnvironmentSettings.swift
//  nextpvr-apple-client
//
//  Response model for Dispatcharr `GET /api/core/settings/env/` (#112).
//
//  Mirrors the live `environment` view in Dispatcharr's
//  `core/api_views.py` (queried against the
//  `Dispatcharr/Dispatcharr` repo at the time of writing). The full
//  payload includes TLS sub-objects that are server-internal
//  diagnostics; we decode them so future fields don't require a
//  model bump, but they're not surfaced in the UI.
//
//  `useOutputEndpoints` mode (HDHR / M3U / XC output URLs) does not
//  expose this endpoint — the caller must check
//  `DispatcherClient.useOutputEndpoints` and skip the call
//  gracefully. The client method `getEnvironmentSettings()` handles
//  that for callers.
//

import Foundation

nonisolated struct EnvironmentSettings: Codable, Equatable, Sendable {
    /// Public IP of the Dispatcharr server, as seen by ipify.org.
    /// Nil when IP lookup is disabled or has not yet completed.
    let publicIP: String?

    /// Local IP of the Dispatcharr server, derived from a UDP socket
    /// connect trick. Not authoritative (it's the routing table, not
    /// the interface address) but useful for the user to know the
    /// "container IP" if they're inside a Docker network.
    let localIP: String?

    /// ISO 3166-1 alpha-2 country code (e.g. "CA", "US"), or nil
    /// if the geolocation lookup failed.
    let countryCode: String?

    let countryName: String?
    let city: String?

    /// Whether IP lookup is enabled at all (env var + DB setting).
    /// When false, the Dispatcharr UI shows a "lookup disabled"
    /// placeholder; clients should mirror that UX.
    let ipLookupEnabled: Bool

    /// True when the cache hasn't been populated yet and Dispatcharr
    /// is running the lookup in the background. The UI should show
    /// a spinner or "looking up..." placeholder while this is true.
    let ipLookupPending: Bool

    /// "aio" (all-in-one), "core", or "dispatcher" — useful for the
    /// support link in the Settings footer but not user-actionable.
    let envMode: String?

    /// Server-internal TLS state. Decoded so the model survives a
    /// Dispatcharr upgrade that adds a field; not surfaced in UI.
    let redisTLS: TLSState?
    let postgresTLS: TLSState?

    enum CodingKeys: String, CodingKey {
        case publicIP = "public_ip"
        case localIP = "local_ip"
        case countryCode = "country_code"
        case countryName = "country_name"
        case city
        case ipLookupEnabled = "ip_lookup_enabled"
        case ipLookupPending = "ip_lookup_pending"
        case envMode = "env_mode"
        case redisTLS = "redis_tls"
        case postgresTLS = "postgres_tls"
    }
}

nonisolated struct TLSState: Codable, Equatable, Sendable {
    let enabled: Bool
    let verify: Bool?
    let mtls: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled
        case verify
        case mtls
    }
}
