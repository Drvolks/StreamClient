//
//  CatchupService.swift
//  nextpvr-apple-client
//
//  Catch-up (timeshift) session lifecycle service for Dispatcharr (#119).
//
//  Wraps `DispatcherClient`'s `startCatchupSession` / `endCatchupSession`
//  with the URL resolution and actor isolation the player view needs:
//
//    - Resolves the relative `playback_url` (e.g.
//      "/proxy/catchup/<uuid>?session_id=<id>") into an absolute
//      URL by concatenating `baseURL` + relative. The server
//      always returns a leading slash, so no scheme juggling.
//
//    - Pins the two TTL constants from the spec (issue #119
//      comment §2) so callers can render "open within 60 s" /
//      "session expires in 10 min idle" UX hints without having
//      to keep the spec open.
//
//    - The `actor` keyword lets the player view mint + revoke in
//      parallel without tripping Swift 6's strict concurrency
//      checker on shared mutable state (there isn't any — the
//      service is stateless — but the actor still earns its keep
//      because mint+revoke races are easier to reason about when
//      the operations are serialised through the actor's queue).
//
//  Lifecycle pattern (the player view does this):
//
//    let response = try await service.startSession(...)
//    let url = try service.playbackURL(for: response)
//    player.open(url)
//    ...
//    await service.endSession(response.sessionId)   // on dispose
//

import Foundation

actor CatchupService {

    /// The fully-qualified base URL of the Dispatcharr server,
    /// including scheme (e.g. "https://dispatcharr.example.com:8000").
    /// Passed in at init rather than read from `client.baseURL` directly —
    /// `DispatcherClient` is `@MainActor`-isolated, and an actor's own init
    /// runs nonisolated, so it can't synchronously read a main-actor
    /// property. The caller (always a `@MainActor` SwiftUI view) reads it
    /// instead.
    private let baseURL: String

    /// The client that owns the JWT / API-key auth headers and
    /// `useOutputEndpoints` flag. The actual REST calls live on
    /// this client so they inherit the same auth path as the rest
    /// of `/api/`.
    private let client: DispatcherClient

    init(client: DispatcherClient, baseURL: String) {
        self.client = client
        self.baseURL = baseURL
    }

    /// Server's 60-second HANDSHAKE_TTL (issue #119 comment §2).
    /// Caller must open the playback URL within this window after
    /// mint. Exposed so the UI can surface a countdown.
    /// Numeric constant mirrors `apps/timeshift/sessions.py`.
    static let handshakeTTLSeconds: Int = 60

    /// Server's 600-second SESSION_IDLE_TTL (10 min sliding
    /// window). Each byte-range GET from the player refreshes it.
    /// Numeric constant mirrors `apps/timeshift/sessions.py`.
    static let idleTTLSeconds: Int = 600

    /// Mint a catch-up playback session for the given channel /
    /// programme start. Throws on the documented error responses:
    /// 400 (invalid `start`, no catch-up streams), 403 (network or
    /// channel ACL), 404 (channel not found), 503 (session service
    /// unavailable).
    func startSession(channelUuid: String, startISO8601: String) async throws -> CatchupSessionCreateResponse {
        try await client.startCatchupSession(channelUuid: channelUuid, startISO8601: startISO8601)
    }

    /// Resolve the server-relative `playback_url` into an absolute
    /// URL by string-concatenating `baseURL + relative`. The server
    /// always returns a leading slash, so this works without scheme
    /// juggling. Throws `URLError(.badURL)` if the concatenation
    /// can't form a valid URL (e.g. `baseURL` is missing a scheme).
    nonisolated func playbackURL(for session: CatchupSessionCreateResponse) throws -> URL {
        // `nonisolated` because URL building has no shared state —
        // safe to call from any context.
        guard let url = URL(string: baseURL + session.playbackUrl) else {
            throw URLError(.badURL)
        }
        return url
    }

    /// Best-effort revoke. 204 = success, 404 = already gone (which
    /// is also success — the server's existence-check deliberately
    /// hides other users' sessions, so a 404 might also mean
    /// "someone else owns it now"). For the caller's purposes the
    /// right action is the same: drop the local reference. Any
    /// other error is swallowed inside `endCatchupSession` because
    /// the server reaps on idle TTL anyway.
    func endSession(_ sessionId: String) async {
        await client.endCatchupSession(sessionId)
    }
}