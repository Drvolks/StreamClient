//
//  LiveTimeshiftTests.swift
//  NexusPVRTests
//
//  Tests for the live timeshift seek rules (issue #126).
//

import Testing
import Foundation
@testable import NextPVR

struct LiveTimeshiftTests {

    @Test("Seeking past the live edge stops short of the write head")
    func clampsToEdgeMargin() {
        let buffer = 600.0
        #expect(LiveTimeshift.clampedTarget(buffer, bufferDuration: buffer) == buffer - LiveTimeshift.edgeMargin)
        #expect(LiveTimeshift.clampedTarget(9999, bufferDuration: buffer) == buffer - LiveTimeshift.edgeMargin)
    }

    @Test("Seeking before the buffer start clamps to zero")
    func clampsToStart() {
        #expect(LiveTimeshift.clampedTarget(-30, bufferDuration: 600) == 0)
        // A buffer shorter than the margin leaves nowhere to go but the start.
        #expect(LiveTimeshift.clampedTarget(5, bufferDuration: 4) == 0)
    }

    @Test("A position inside the buffer passes through unchanged")
    func passesThroughInteriorPositions() {
        #expect(LiveTimeshift.clampedTarget(120, bufferDuration: 600) == 120)
    }

    @Test("Skipping forward while paused lands at the live edge, not past it")
    func skipForwardFromPausedPositionStaysSeekable() {
        // Paused 20s behind live, then +30s skip: the request overshoots the head
        // and has to come back to the margin rather than reopening past it.
        let buffer = 600.0
        let target = LiveTimeshift.clampedTarget(buffer - 20 + 30, bufferDuration: buffer)
        #expect(target == buffer - LiveTimeshift.edgeMargin)
        #expect(target < buffer)
    }

    @Test("EOF right after a live seek is retried rather than ending playback")
    func eofSoonAfterSeekIsRecoverable() {
        #expect(LiveTimeshift.shouldRetryAfterEOF(secondsSinceLastSeek: 0.5, retryCount: 0))
        #expect(LiveTimeshift.shouldRetryAfterEOF(secondsSinceLastSeek: 5, retryCount: 2))
    }

    @Test("EOF unrelated to a seek ends playback normally")
    func eofOutsideTheWindowIsNotRecovered() {
        #expect(!LiveTimeshift.shouldRetryAfterEOF(secondsSinceLastSeek: 60, retryCount: 0))
        // A stream that never started has .distantPast as its last seek.
        let sinceNever = Date().timeIntervalSince(.distantPast)
        #expect(!LiveTimeshift.shouldRetryAfterEOF(secondsSinceLastSeek: sinceNever, retryCount: 0))
    }

    @Test("Retries give up so a genuinely dead stream still ends")
    func retriesAreBounded() {
        #expect(!LiveTimeshift.shouldRetryAfterEOF(
            secondsSinceLastSeek: 0.5,
            retryCount: LiveTimeshift.maxEdgeRetries
        ))
    }

    @Test("Each retry reopens further back than the last")
    func retryTargetsStepBackwards() {
        let position = 592.0
        let first = LiveTimeshift.retryTarget(from: position, attempt: 1)
        let second = LiveTimeshift.retryTarget(from: position, attempt: 2)
        #expect(first == position - LiveTimeshift.edgeMargin)
        #expect(second < first)
    }

    @Test("Retrying near the buffer start clamps to zero instead of going negative")
    func retryTargetClampsToStart() {
        #expect(LiveTimeshift.retryTarget(from: 4, attempt: 3) == 0)
    }
}
