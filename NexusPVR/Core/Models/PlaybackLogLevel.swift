//
//  PlaybackLogLevel.swift
//  PVR Client
//
//  Severity of a line in a playback session log.
//

import Foundation

/// Severity of one line in a `PlaybackSession`: mpv's own log levels plus
/// `event`, for the player milestones the app writes itself (file loaded,
/// audio output opened, player closed, ...).
nonisolated enum PlaybackLogLevel: String, Sendable, Equatable, CaseIterable {
    case fatal
    case error
    case warn
    case info
    case verbose = "v"
    case debug
    case trace
    case event

    /// mpv's level string ("error", "warn", "v", ...); anything unknown is info.
    init(mpvLevel: String) {
        self = PlaybackLogLevel(rawValue: mpvLevel) ?? .info
    }

    /// Fatal and error lines make a session count as a problem.
    var isProblem: Bool {
        self == .fatal || self == .error
    }

    /// Short tag for the log view and the shared text.
    var tag: String {
        switch self {
        case .fatal: return "FATAL"
        case .error: return "ERROR"
        case .warn: return "WARN"
        case .info: return "info"
        case .verbose: return "v"
        case .debug: return "debug"
        case .trace: return "trace"
        case .event: return "APP"
        }
    }
}
