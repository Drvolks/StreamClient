//
//  StalledRecordingRecoveryTests.swift
//  NexusPVRTests
//
//  Tests for recovering an in-progress recording stalled at the write edge
//  (issue #127).
//

import Testing
import Foundation
@testable import NextPVR

struct StalledRecordingRecoveryTests {

    /// Playback parked at the write edge after fast-forwarding: the demuxer's EOF
    /// retry loop never resolves this, so it has to be reopened.
    private func stalledAtEdge(
        stalledFor: TimeInterval = 3,
        sinceLastReload: TimeInterval = 60,
        lastReloadTarget: Double? = nil
    ) -> Bool {
        StalledRecordingRecovery.shouldReload(
            position: 1800,
            knownEnd: 1830,
            stalledFor: stalledFor,
            sinceLastReload: sinceLastReload,
            lastReloadTarget: lastReloadTarget
        )
    }

    @Test("A recording stalled at the live edge is reopened")
    func stallAtEdgeTriggersReload() {
        #expect(stalledAtEdge())
    }

    @Test("A brief rebuffer is left alone")
    func shortStallIsIgnored() {
        #expect(!stalledAtEdge(stalledFor: 1))
    }

    @Test("Reopens are rate limited so they can't loop")
    func cooldownBlocksRepeatReloads() {
        #expect(!stalledAtEdge(sinceLastReload: 5))
        #expect(stalledAtEdge(sinceLastReload: StalledRecordingRecovery.reloadCooldown))
    }

    @Test("A second reopen onto the same content is skipped")
    func repeatedTargetIsSkipped() {
        // 1830 - 30 backoff = 1800; a previous reopen that aimed there didn't help.
        #expect(!stalledAtEdge(lastReloadTarget: 1800))
        // Once the recording has grown, the target has moved on and it's worth retrying.
        #expect(stalledAtEdge(lastReloadTarget: 1700))
    }

    @Test("Nothing is reopened when the server has no content ahead")
    func noReloadWithoutContentAhead() {
        // Caught up with everything that has been recorded — waiting is correct.
        #expect(!StalledRecordingRecovery.shouldReload(
            position: 1800,
            knownEnd: 1802,
            stalledFor: 5,
            sinceLastReload: 60,
            lastReloadTarget: nil
        ))
    }

    @Test("Startup is not mistaken for a stall")
    func startupIsNotAStall() {
        #expect(!StalledRecordingRecovery.shouldReload(
            position: 0,
            knownEnd: 1800,
            stalledFor: 5,
            sinceLastReload: 60,
            lastReloadTarget: nil
        ))
    }

    @Test("Reopening backs off from the edge")
    func targetBacksOffFromEdge() {
        #expect(StalledRecordingRecovery.reloadTarget(position: 1800, knownEnd: 1830)
            == 1830 - StalledRecordingRecovery.edgeBackoff)
    }

    @Test("A stall far from the edge reopens in place, without skipping ahead")
    func midFileStallKeepsPosition() {
        // A network hiccup 100s into a 1h recording must not fast-forward the
        // viewer to the live edge.
        #expect(StalledRecordingRecovery.reloadTarget(position: 100, knownEnd: 3600) == 100)
    }

    @Test("A recording shorter than the backoff reopens where it is")
    func shortRecordingTargetStaysInRange() {
        let target = StalledRecordingRecovery.reloadTarget(position: 12, knownEnd: 20)
        #expect(target >= 0)
        #expect(target <= 12)
    }
}
