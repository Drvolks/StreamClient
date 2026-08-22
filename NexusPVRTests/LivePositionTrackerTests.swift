//
//  LivePositionTrackerTests.swift
//  NexusPVRTests
//
//  Tests for the live timeshift position clock (issue #148).
//

import Testing
import Foundation
@testable import NextPVR

struct LivePositionTrackerTests {

    /// Feeds one second of playback per sample, the way a healthy live stream
    /// reports it.
    private func play(
        _ tracker: inout LivePositionTracker,
        seconds: Int,
        from playerPosition: Double,
        at start: Date
    ) -> (playerPosition: Double, now: Date) {
        var playerPosition = playerPosition
        var now = start
        for _ in 0..<seconds {
            playerPosition += 1
            now = now.addingTimeInterval(1)
            tracker.update(playerPosition: playerPosition, now: now)
        }
        return (playerPosition, now)
    }

    @Test("Steady playback advances the buffer position in real time")
    func steadyPlaybackAccumulates() {
        let start = Date()
        var tracker = LivePositionTracker()
        tracker.update(playerPosition: 0, now: start)
        _ = play(&tracker, seconds: 300, from: 0, at: start)
        #expect(tracker.position == 300)
    }

    @Test("A paused stream holds its position")
    func pausedPlaybackHoldsPosition() {
        let start = Date()
        var tracker = LivePositionTracker()
        tracker.update(playerPosition: 0, now: start)
        let played = play(&tracker, seconds: 60, from: 0, at: start)

        // mpv repeats the same time-pos while paused, wall clock keeps going.
        var now = played.now
        for _ in 0..<120 {
            now = now.addingTimeInterval(1)
            tracker.update(playerPosition: played.playerPosition, now: now)
        }
        #expect(tracker.position == 60)
    }

    @Test("mpv restarting its clock mid-stream costs one sample, not the session")
    func discontinuityDoesNotDesynchronise() {
        let start = Date()
        var tracker = LivePositionTracker()
        tracker.update(playerPosition: 0, now: start)
        let first = play(&tracker, seconds: 600, from: 0, at: start)
        #expect(tracker.position == 600)

        // A PTS discontinuity (or an mpv-internal reopen) drops time-pos back to
        // near zero. The old `base + time-pos` reading would have collapsed to ~0
        // here; the tracker keeps the position it earned.
        let after = play(&tracker, seconds: 600, from: 0, at: first.now)
        #expect(tracker.position >= 1199 && tracker.position <= 1200)
        #expect(after.playerPosition == 600)
    }

    @Test("A forward jump is capped at the wall-clock time that actually passed")
    func forwardJumpIsCappedByWallClock() {
        let start = Date()
        var tracker = LivePositionTracker()
        tracker.update(playerPosition: 0, now: start)
        _ = play(&tracker, seconds: 60, from: 0, at: start)

        // A 33-bit PTS rollover reports an enormous forward step across one tick.
        tracker.update(playerPosition: 95_443, now: start.addingTimeInterval(61))
        #expect(tracker.position <= 61 + LivePositionTracker.driftTolerance)
    }

    @Test("A live seek re-anchors the position at the requested buffer offset")
    func seekAnchorsAtTarget() {
        let start = Date()
        var tracker = LivePositionTracker()
        tracker.update(playerPosition: 0, now: start)
        let played = play(&tracker, seconds: 120, from: 0, at: start)

        // Reopening at a byte offset restarts mpv near zero.
        tracker.anchor(at: 3_000)
        #expect(tracker.position == 3_000)

        var now = played.now
        now = now.addingTimeInterval(1)
        tracker.update(playerPosition: 0, now: now)
        let resumed = play(&tracker, seconds: 30, from: 0, at: now)
        #expect(tracker.position == 3_030)
        #expect(resumed.playerPosition == 30)
    }

    /// The reported bug: after a long session the UI claimed roughly an hour
    /// behind live while playback was near the edge, and skipping forward from
    /// that position reopened the stream near the start of the buffer.
    @Test("A long live session with origin resets stays near the live edge")
    func longRunningSessionReportsAccurateDelay() {
        let start = Date()
        var tracker = LivePositionTracker()
        tracker.update(playerPosition: 0, now: start)

        // Two hours of playback, with mpv's clock restarting every 20 minutes.
        var now = start
        // Server-side stream_duration, growing in real time. Playback opened a
        // few seconds after the buffer did, so it trails it by that much.
        var buffer = 20.0
        for _ in 0..<6 {
            let segment = play(&tracker, seconds: 1_200, from: 0, at: now)
            now = segment.now
            buffer += 1_200
            tracker.update(playerPosition: 0, now: now)  // origin reset
        }

        let behindLive = max(0, buffer - tracker.position)
        // At most the handful of samples lost to the resets — nowhere near the
        // tens of minutes reported in #148.
        #expect(behindLive < 60)

        // And a skip forward from there still moves toward the live edge.
        let target = LiveTimeshift.clampedTarget(tracker.position + 30, bufferDuration: buffer)
        #expect(target > tracker.position)
        #expect(target <= buffer - LiveTimeshift.edgeMargin)
    }

    @Test("A stream that opens with a non-zero mpv clock still starts at the buffer start")
    func nonZeroStartOriginIsIgnored() {
        let start = Date()
        var tracker = LivePositionTracker()
        // Raw MPEG-TS often reports a large first timestamp.
        tracker.update(playerPosition: 44_100, now: start)
        _ = play(&tracker, seconds: 90, from: 44_100, at: start)
        #expect(tracker.position == 90)
    }
}
