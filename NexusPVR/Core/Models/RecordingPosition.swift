//
//  RecordingPosition.swift
//  DispatcherPVR
//
//  A recording's resume position and when it was saved (#183)
//

import Foundation

nonisolated struct RecordingPosition: Codable, Equatable, Sendable {
    /// Seconds into the recording. 0 means "watch from the beginning" — it is
    /// kept as an entry rather than removed, so it wins over an older position
    /// on another device.
    let position: Int
    let updatedAt: Date

    /// Which of two entries for the same recording to keep: the newer one, and
    /// on a tie the further position, so every device picks the same winner.
    func supersedes(_ other: RecordingPosition) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        return position > other.position
    }
}
