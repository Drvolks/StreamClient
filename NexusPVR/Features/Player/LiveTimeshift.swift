//
//  LiveTimeshift.swift
//  nextpvr-apple-client
//
//  Pure timeshift math for the live seek path, factored out of PlayerView so the
//  clamping and EOF-retry rules can be exercised without a running player.
//

import Foundation

nonisolated enum LiveTimeshift {
    /// Never seek right up to the write head — the last moments of the buffer may
    /// not be fully flushed, which yields a truncated frame and an immediate EOF.
    static let edgeMargin: Double = 8

    /// Below this the timeshift bar isn't worth offering.
    static let minimumBuffer: Double = 30

    /// How long after a live reload an EOF is read as "reopened past the write
    /// head" rather than "the stream ended".
    static let eofWindow: Double = 6

    static let maxEdgeRetries = 3

    /// Debounce applied to skip presses before they turn into a reload. Long
    /// enough to absorb a tvOS hold-to-scrub burst (one tick every 250ms), short
    /// enough that a single press still feels immediate.
    static let seekCommitDelay: Duration = .milliseconds(400)

    /// Clamps a requested buffer position into the seekable range.
    static func clampedTarget(_ position: Double, bufferDuration: Double) -> Double {
        min(max(0, position), max(0, bufferDuration - edgeMargin))
    }

    /// Whether an end-of-file should be treated as a live reload landing past the
    /// server's flushed write head — recoverable — rather than the stream ending.
    static func shouldRetryAfterEOF(secondsSinceLastSeek: Double, retryCount: Int) -> Bool {
        secondsSinceLastSeek < eofWindow && retryCount < maxEdgeRetries
    }

    /// Where to reopen after an EOF. Each attempt drops further back — the offset
    /// that just failed already proved it wasn't readable yet.
    static func retryTarget(from position: Double, attempt: Int) -> Double {
        max(0, position - Double(attempt) * edgeMargin)
    }
}
