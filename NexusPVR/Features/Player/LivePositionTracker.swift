//
//  LivePositionTracker.swift
//  PVR Client
//
//  Keeps the live timeshift position on the same clock as the server-side
//  buffer (issue #148).
//

import Foundation

/// Where playback sits inside NextPVR's timeshift buffer, in seconds from the
/// start of the buffer.
///
/// mpv's `time-pos` can't be used as that clock directly. It is derived from the
/// broadcast's MPEG-TS timestamps, so it restarts or jumps at a PTS
/// discontinuity and wraps on a long enough session, and it also drops back to
/// ~0 whenever the stream is reopened — which the live seek path does on every
/// skip, and mpv's own recovery does on an EOF. Adding a fixed base offset to it
/// therefore drifts away from the server's `stream_duration` origin: the UI ends
/// up claiming an hour behind live while playback is still near the edge, and
/// the next skip-forward, seeking relative to that bogus position, reopens the
/// stream near the start of the buffer (#148).
///
/// So this integrates *increments* of `time-pos` rather than trusting its
/// origin. Increments that can't be real playback — negative ones from a reload
/// or discontinuity, or ones larger than the wall-clock time that has actually
/// passed — are discarded, and the position is re-anchored explicitly whenever a
/// seek puts it at a known place in the buffer. Worst case a discontinuity costs
/// one poll interval of position, instead of desynchronising the clock for the
/// rest of the session.
nonisolated struct LivePositionTracker: Equatable {
    /// Slack on the wall-clock bound. Live playback runs at 1x, but samples
    /// arrive on a timer and mpv plays a short catch-up burst after a rebuffer,
    /// so an increment slightly ahead of elapsed time is still genuine.
    static let driftTolerance: Double = 1

    /// Buffer position of the current playback point, seconds from buffer start.
    private(set) var position: Double = 0

    private var lastSample: Double?
    private var lastSampleAt: Date?

    init(position: Double = 0) {
        self.position = max(0, position)
    }

    /// Re-anchors at a known buffer position — a completed live seek. The next
    /// sample only re-arms the increment baseline, since mpv's position in the
    /// reopened stream has a new origin.
    mutating func anchor(at position: Double) {
        self.position = max(0, position)
        lastSample = nil
        lastSampleAt = nil
    }

    /// Feeds one mpv `time-pos` sample.
    mutating func update(playerPosition: Double, now: Date = Date()) {
        defer {
            lastSample = playerPosition
            lastSampleAt = now
        }
        guard let lastSample, let lastSampleAt else { return }

        let delta = playerPosition - lastSample
        // Paused or stalled (0), or a reload/discontinuity moved the origin
        // (negative) — either way no playback time can be credited.
        guard delta > 0 else { return }

        let elapsed = max(0, now.timeIntervalSince(lastSampleAt))
        position += min(delta, elapsed + Self.driftTolerance)
    }
}
