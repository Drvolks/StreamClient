//
//  CatchupSession.swift
//  nextpvr-apple-client
//
//  Dispatcharr catch-up (timeshift) session models (#119).
//
//  Two Codable structs cover the mint / playback lifecycle for the
//  Dispatcharr `/api/catchup/sessions/` REST API. Spec from issue
//  #119's pinned comment (Dispatcharr commit 223dff33).
//
//  Lifecycle:
//    POST   /api/catchup/sessions/      → CatchupSessionCreateResponse
//    DELETE /api/catchup/sessions/{id}/ → 204 No Content (best-effort)
//
//  The server has two TTLs the client must respect:
//    HANDSHAKE_TTL_SECONDS     = 60   (mint → first playback GET)
//    SESSION_IDLE_TTL_SECONDS  = 600  (sliding, refreshed on each
//                                     byte-range GET — see #119
//                                     comment for the full table)
//
//  Use one session per programme. Don't reuse across two shows — the
//  `start` is fixed at mint time.
//

import Foundation

/// Request body for `POST /api/catchup/sessions/`.
nonisolated struct CatchupSessionRequest: Codable, Equatable, Sendable {
    /// Dispatcharr channel UUID, not the legacy numeric id.
    /// `DispatcharrChannel.uuid` is the source of truth.
    let channelUuid: String

    /// Programme broadcast start time in UTC. Selects which
    /// archived show to fetch, not when the viewer pressed play.
    /// Dispatcharr accepts ISO-8601 / Unix epoch / XC wall-clock
    /// (see `parse_catchup_timestamp` in `apps/timeshift/helpers.py`).
    /// Always send as ISO-8601 from `Program.startDate`.
    let start: String

    enum CodingKeys: String, CodingKey {
        case channelUuid = "channel_uuid"
        case start
    }

    init(channelUuid: String, startISO8601: String) {
        self.channelUuid = channelUuid
        self.start = startISO8601
    }
}

/// Response body from `POST /api/catchup/sessions/`.
nonisolated struct CatchupSessionCreateResponse: Codable, Equatable, Sendable {
    /// Opaque session token. Acts as the credential for both the
    /// `DELETE` revoke and the playback URL `?session_id=` query.
    /// Treat as bearer-secret — don't log it.
    let sessionId: String

    /// Server-relative playback URL. Concatenate with `baseURL` to
    /// get the absolute URL for `MPVPlayerCore`. Example:
    ///   "/proxy/catchup/abc123?session_id=xyz789"
    let playbackUrl: String

    /// Server-side hard expiry, Unix seconds. The session dies
    /// `expires_at - now` seconds after this timestamp; mirror
    /// it client-side as a "session expired" UX hint.
    let expiresAt: Int

    /// Echo of the request `channel_uuid`. Useful for confirmation
    /// and for client-side audit logs.
    let channelUuid: String

    /// Echo of the request `start` (ISO-8601). Useful for
    /// confirmation and for "started programme X at Y" log lines.
    let start: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case playbackUrl = "playback_url"
        case expiresAt = "expires_at"
        case channelUuid = "channel_uuid"
        case start
    }
}