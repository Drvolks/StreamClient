//
//  DownloadSource.swift
//  NexusPVR
//
//  Where the bytes of an offline download come from.
//

import Foundation

/// Identifies what a `DownloadItem` was made from, so a failed download can be
/// retried by resolving a *fresh* URL rather than reusing a stale one. Both
/// cases resolve to "an HTTP URL plus auth headers" at download time — the
/// catch-up case has to mint a new session (they expire), and the recording
/// case has to re-resolve because NextPVR bakes a session id into the URL.
nonisolated enum DownloadSource: Codable, Equatable, Hashable, Sendable {
    /// A Dispatcharr catch-up (timeshift) programme. `start` is the
    /// programme's scheduled broadcast start, which is what
    /// `POST /api/catchup/sessions/` keys off — see `CatchupSessionRequest`.
    case catchup(channelUuid: String, start: Date)

    /// A completed server-side recording, resolved through
    /// `PVRClientProtocol.recordingStreamURL(recordingId:)`. Works for both
    /// the NextPVR and Dispatcharr variants.
    case recording(id: Int)
}
