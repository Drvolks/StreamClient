//
//  RecordingWatchState.swift
//  nextpvr-apple-client
//
//  Whether a completed recording is new, part-watched or watched, as shown
//  by the macOS recordings list (Midnight redesign).
//

import Foundation

nonisolated enum RecordingWatchState: Equatable {
    /// Never played (or only an accidental few seconds).
    case new
    /// Part-watched; `progress` is the fraction played, 0 < progress < 1.
    case resume(progress: Double)
    case watched

    init(_ recording: Recording) {
        if recording.isWatched {
            self = .watched
        } else if recording.hasResumePosition,
                  let position = recording.playbackPosition,
                  let duration = recording.duration, duration > 0 {
            self = .resume(progress: min(max(Double(position) / Double(duration), 0), 1))
        } else {
            self = .new
        }
    }

    var label: String {
        switch self {
        case .new: "New"
        case .resume: "Resume"
        case .watched: "Watched"
        }
    }
}
