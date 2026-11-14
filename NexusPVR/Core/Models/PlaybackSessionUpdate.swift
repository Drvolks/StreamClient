//
//  PlaybackSessionUpdate.swift
//  PVR Client
//
//  A change to a playback session, sent from the player to the Event Log.
//

import Foundation

/// A change to one `PlaybackSession`, sent by `MPVPlayerCore` (any thread)
/// to `NetworkEventLogging.logPlayback(_:)`.
nonisolated struct PlaybackSessionUpdate: Sendable, Equatable {
    let sessionId: UUID
    let timestamp: Date
    let kind: PlaybackSessionUpdateKind

    init(sessionId: UUID, timestamp: Date = Date(), kind: PlaybackSessionUpdateKind) {
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.kind = kind
    }
}
