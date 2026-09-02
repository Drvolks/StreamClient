//
//  DownloadPolicy.swift
//  NexusPVR
//
//  Pure decision math for offline downloads: when to stop writing, and how far
//  along a running download is.
//

import Foundation

/// A catch-up session's archive is not the programme. `POST /api/catchup/sessions/`
/// fixes only `start`, and the upstream URL it builds runs from there to the
/// live edge as it stood at mint time (see `CatchupContinuation`). Downloading
/// a show that aired two days ago therefore hands us two days of stream unless
/// the client stops itself — which is what this decides.
nonisolated enum DownloadPolicy {

    /// Extra programme kept past the scheduled end, to absorb broadcasts that
    /// overrun and EPG start times that are a little early.
    static let catchupTailSeconds: Double = 60

    /// Refuse to start unless this much free space is available. A conservative
    /// floor: an hour of HD MPEG-TS is comfortably under 4 GB, and the archive
    /// size isn't known up front, so this is a sanity check rather than an
    /// accurate reservation.
    static let minimumFreeBytes: Int64 = 4 * 1024 * 1024 * 1024

    /// Whether the job has written everything it was asked for and should stop.
    /// Sources with no `expectedDuration` (a recording file) run to their own
    /// end of stream.
    static func shouldStop(writtenSeconds: Double, expectedDuration: Double?) -> Bool {
        guard let expectedDuration, expectedDuration > 0 else { return false }
        return writtenSeconds >= expectedDuration
    }

    /// Fraction complete in 0...1, or `nil` when the total isn't known and the
    /// UI should show an indeterminate indicator instead.
    static func progress(writtenSeconds: Double, expectedDuration: Double?) -> Double? {
        guard let expectedDuration, expectedDuration > 0 else { return nil }
        return min(1, max(0, writtenSeconds / expectedDuration))
    }

    /// Whether a finished file holds enough of the programme to be worth
    /// keeping. A download that dies in the first few seconds leaves an `.mp4`
    /// with no usable content, and offering it for playback is worse than
    /// reporting the failure.
    static func isUsable(writtenSeconds: Double) -> Bool {
        writtenSeconds >= minimumUsableSeconds
    }

    /// Below this, a finished file counts as an empty failure rather than a
    /// short recording.
    static let minimumUsableSeconds: Double = 5
}
