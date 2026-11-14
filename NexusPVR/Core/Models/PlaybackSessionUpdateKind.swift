//
//  PlaybackSessionUpdateKind.swift
//  PVR Client
//
//  What a playback session update does.
//

import Foundation

/// What a `PlaybackSessionUpdate` does to its session.
nonisolated enum PlaybackSessionUpdateKind: Sendable, Equatable {
    /// Opens the session and adds its row to the Event Log.
    case start(title: String, host: String?)
    /// Adds a line to the session's log.
    case line(PlaybackLogLevel, String)
    /// Records how the session ended. A failure is kept over a later normal end.
    case end(PlaybackSessionOutcome)
}
