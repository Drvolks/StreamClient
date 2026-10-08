//
//  DispatcharrSessionStore.swift
//  nextpvr-apple-client
//
//  Keeps the Dispatcharr JWT pair between launches, and shares it between
//  the app and its Top Shelf extension (App Group defaults). Dispatcharr
//  rate-limits sign-ins: without this every launch signed in, and so did
//  each Top Shelf reload — up to three times — which left the app's own
//  sign-in throttled (HTTP 429) for most of a minute at launch.
//
//  A saved access token is used while it is valid, then renewed with the
//  refresh token; only when neither works is a sign-in needed.
//

import CryptoKit
import Foundation

nonisolated enum DispatcharrSessionStore {
    private static let storageKey = "DispatcharrSession"

    /// App Group defaults where there is one (tvOS shares them with the Top
    /// Shelf extension), the app's own otherwise.
    static var sharedDefaults: UserDefaults {
        let suite = ServerConfig.appGroupSuite
        guard !suite.isEmpty, let defaults = UserDefaults(suiteName: suite) else { return .standard }
        return defaults
    }

    /// Identifies the server and login a session belongs to, without
    /// storing the password again: a changed password must sign in anew.
    static func credentialKey(for config: ServerConfig) -> String {
        let material = "\(config.baseURL)|\(config.username)|\(config.password)"
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The saved session for `config`, or nil when there is none or it was
    /// made with another server or login.
    static func load(for config: ServerConfig, defaults: UserDefaults = sharedDefaults) -> DispatcharrSession? {
        guard let data = defaults.data(forKey: storageKey),
              let session = try? JSONDecoder().decode(DispatcharrSession.self, from: data),
              session.credentialKey == credentialKey(for: config) else { return nil }
        return session
    }

    static func save(
        access: String,
        refresh: String?,
        for config: ServerConfig,
        defaults: UserDefaults = sharedDefaults
    ) {
        let session = DispatcharrSession(access: access, refresh: refresh, credentialKey: credentialKey(for: config))
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func clear(defaults: UserDefaults = sharedDefaults) {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: Standalone use (Top Shelf fetchers)

    /// A usable access token for `config`: the saved one while valid, else
    /// renewed with the refresh token, else from a sign-in. For code that
    /// runs outside the app's client, such as the Top Shelf extension.
    static func accessToken(config: ServerConfig, session: URLSession) async throws -> String {
        if let saved = load(for: config) {
            if JWTExpiry.isValid(saved.access) { return saved.access }
            if let refresh = saved.refresh,
               let renewed = try? await renew(refresh: refresh, config: config, session: session) {
                return renewed
            }
        }
        return try await signIn(config: config, session: session)
    }

    private struct TokenPair: Decodable {
        let access: String
        let refresh: String?
    }

    private static func renew(refresh: String, config: ServerConfig, session: URLSession) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/api/accounts/token/refresh/") else {
            throw URLError(.badURL)
        }
        let pair = try await post(["refresh": refresh], to: url, session: session)
        // Servers that rotate refresh tokens send a new one; keep the old otherwise.
        save(access: pair.access, refresh: pair.refresh ?? refresh, for: config)
        return pair.access
    }

    private static func signIn(config: ServerConfig, session: URLSession) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/api/accounts/token/") else {
            throw URLError(.badURL)
        }
        let pair = try await post(["username": config.username, "password": config.password], to: url, session: session)
        save(access: pair.access, refresh: pair.refresh, for: config)
        return pair.access
    }

    private static func post(_ body: [String: String], to url: URL, session: URLSession) async throws -> TokenPair {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }
        return try JSONDecoder().decode(TokenPair.self, from: data)
    }
}
