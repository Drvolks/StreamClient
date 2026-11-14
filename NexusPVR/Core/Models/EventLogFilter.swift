//
//  EventLogFilter.swift
//  PVR Client
//
//  Which Event Log rows to show.
//

import Foundation

/// Which rows the Event Log shows.
nonisolated enum EventLogFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    /// Failed requests and playback sessions with errors.
    case problems
    /// Playback sessions only.
    case playback

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .problems: return "Problems"
        case .playback: return "Playback"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "No network events yet"
        case .problems: return "No problems recorded"
        case .playback: return "No playback recorded yet"
        }
    }

    /// `session` is the playback session the event stands for, if any.
    func includes(_ event: NetworkEvent, session: PlaybackSession?) -> Bool {
        switch self {
        case .all:
            return true
        case .problems:
            if event.sessionId != nil { return session?.hasProblems ?? false }
            return !event.isSuccess
        case .playback:
            return event.sessionId != nil
        }
    }
}
