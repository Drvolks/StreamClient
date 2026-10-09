//
//  VODProgress.swift
//  DispatcherPVR
//
//  How far a VOD movie or episode has been played (#17). Dispatcharr keeps
//  no per-user position for VOD, so the app does, in `VODProgressStore`.
//

import Foundation

nonisolated struct VODProgress: Codable, Equatable, Sendable {
    /// Seconds played.
    var position: Int
    /// Seconds in total, as the player reported it.
    var duration: Int
    var updatedAt: Date

    /// Same thresholds as `Recording`: watched at 90%, and the first few
    /// seconds don't count as started.
    var isWatched: Bool {
        duration > 0 && position > 0 && Double(position) / Double(duration) >= 0.9
    }

    var hasResumePosition: Bool { position > 10 && !isWatched }

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(Double(position) / Double(duration), 0), 1)
    }

    /// Which of two entries for the same item to keep when merging devices
    /// (#183): the newer one, and on a tie the further one, so every device
    /// picks the same winner.
    func supersedes(_ other: VODProgress) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if position != other.position { return position > other.position }
        return duration > other.duration
    }

    var watchState: RecordingWatchState {
        if isWatched { return .watched }
        if hasResumePosition { return .resume(progress: fraction) }
        return .new
    }
}
