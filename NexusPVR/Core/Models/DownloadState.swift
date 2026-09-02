//
//  DownloadState.swift
//  NexusPVR
//
//  Lifecycle state of one offline download.
//

import Foundation

/// The live state of a download. Persisted in the sidecar alongside the media
/// file so a download interrupted by app termination is recognisable as such on
/// the next launch (see `DownloadStore.scan()`), rather than looking complete.
nonisolated enum DownloadState: Codable, Equatable, Hashable, Sendable {
    /// Accepted, waiting for the single download slot.
    case queued
    /// Actively fetching. `seconds` is how much programme has been written so
    /// far — the only progress measure that means anything here, because the
    /// total byte size of a catch-up archive is unknown up front.
    case running(seconds: Double, bytes: Int64)
    /// The file on disk is complete and playable.
    case completed
    /// Stopped without a usable file. The message is shown in the row.
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .queued, .running: return true
        case .completed, .failed: return false
        }
    }
}
