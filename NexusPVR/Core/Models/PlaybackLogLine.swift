//
//  PlaybackLogLine.swift
//  PVR Client
//
//  One line in a playback session log.
//

import Foundation

/// One line in a `PlaybackSession`. Identical consecutive lines are folded
/// into one with a `repeatCount`, so a stream that repeats the same warning
/// doesn't push the start of the session out of the log.
nonisolated struct PlaybackLogLine: Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: PlaybackLogLevel
    let text: String
    var repeatCount: Int

    init(id: UUID = UUID(), timestamp: Date, level: PlaybackLogLevel, text: String, repeatCount: Int = 1) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.text = text
        self.repeatCount = repeatCount
    }
}
