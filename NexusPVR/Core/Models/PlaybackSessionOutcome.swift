//
//  PlaybackSessionOutcome.swift
//  PVR Client
//
//  How a playback session ended.
//

import Foundation

/// How a `PlaybackSession` ended, or that it is still going.
nonisolated enum PlaybackSessionOutcome: Sendable, Equatable {
    case inProgress
    /// Closed normally, e.g. the viewer left the player or the file ended.
    case ended(String)
    /// mpv stopped on an error.
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .inProgress: return "In progress"
        case .ended(let reason): return reason
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}
