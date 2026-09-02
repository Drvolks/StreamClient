//
//  PacketTimelineTests.swift
//  NexusPVRTests
//
//  Coverage for the packet timestamp normalisation behind offline downloads.
//

import Testing
import Foundation
@testable import NextPVR

struct PacketTimelineTests {

    /// 90 kHz, the MPEG-TS clock.
    private let tick = 1.0 / 90_000.0

    private func timeline(anchor: Int64 = 0) -> PacketTimeline {
        PacketTimeline(secondsPerTick: tick, anchor: anchor)
    }

    @Test("Rebases a broadcast clock so the file starts at zero")
    func rebasesToZero() {
        // A mux whose clock is 40000 s in — what a real recording looks like.
        let start: Int64 = 40_000 * 90_000
        var timeline = timeline(anchor: start)

        let first = timeline.normalize(pts: start, dts: start, duration: 3600)
        #expect(first == PacketTimeline.Timestamps(pts: 0, dts: 0))

        let second = timeline.normalize(pts: start + 3600, dts: start + 3600, duration: 3600)
        #expect(second == PacketTimeline.Timestamps(pts: 3600, dts: 3600))
    }

    @Test("Keeps B-frame reordering intact")
    func keepsReordering() {
        let start: Int64 = 3_600_118_800
        var timeline = timeline(anchor: start)

        // pts ahead of dts is normal with B-frames; both shift by the same
        // offset, so the gap between them survives.
        let result = timeline.normalize(pts: start + 7200, dts: start, duration: 3600)
        #expect(result == PacketTimeline.Timestamps(pts: 7200, dts: 0))
    }

    @Test("Decode timestamps come out strictly increasing")
    func strictlyIncreasing() {
        var timeline = timeline()

        _ = timeline.normalize(pts: 0, dts: 0, duration: 3600)
        // A repeated dts is what makes a muxer reject the packet outright.
        let repeated = timeline.normalize(pts: 0, dts: 0, duration: 3600)
        #expect(repeated?.dts == 1)
        #expect(repeated!.pts >= repeated!.dts)
    }

    @Test("A backwards jump carries on instead of rewinding the file")
    func backwardsDiscontinuity() {
        var timeline = timeline()

        _ = timeline.normalize(pts: 90_000, dts: 90_000, duration: 3600)
        let afterJump = timeline.normalize(pts: 100, dts: 100, duration: 3600)

        // The ad-break splice resets the source clock; output time must not go
        // backwards, and the recording must not appear to restart.
        #expect(afterJump != nil)
        #expect(afterJump!.dts == 90_001)
    }

    @Test("A huge forward jump doesn't inflate the duration")
    func forwardDiscontinuity() {
        var timeline = timeline()

        _ = timeline.normalize(pts: 0, dts: 0, duration: 3600)
        // An hour-long leap in the source clock is a break, not an hour of
        // programme — otherwise a 40-minute show measures 65,000 seconds.
        let afterJump = timeline.normalize(pts: 3600 * 90_000, dts: 3600 * 90_000, duration: 3600)
        #expect(afterJump!.dts == 1)

        // And it carries on normally from there.
        let next = timeline.normalize(pts: 3600 * 90_000 + 3600, dts: 3600 * 90_000 + 3600, duration: 3600)
        #expect(next!.dts == 3601)
    }

    @Test("A jump right at the threshold still counts as playback")
    func belowThresholdIsNotADiscontinuity() {
        var timeline = timeline()
        _ = timeline.normalize(pts: 0, dts: 0, duration: 3600)

        let gap = Int64(PacketTimeline.discontinuityThresholdSeconds * 90_000) - 1
        let next = timeline.normalize(pts: gap, dts: gap, duration: 3600)
        #expect(next!.dts == gap)
    }

    @Test("A packet with only a presentation timestamp is still placed")
    func missingDecodeTimestamp() {
        // The anchor is the file's first timestamp, which is this packet's pts
        // — the remuxer falls back to pts exactly as this does.
        var timeline = timeline(anchor: 4500)
        let result = timeline.normalize(pts: 4500, dts: nil, duration: 3600)
        #expect(result == PacketTimeline.Timestamps(pts: 0, dts: 0))
    }

    @Test("An untimed packet is dropped at the start and carried later")
    func missingBothTimestamps() {
        var timeline = timeline()

        // Nothing to anchor to yet — the MP4 muxer rejects a packet with no
        // timestamp, so it goes no further.
        #expect(timeline.normalize(pts: nil, dts: nil, duration: 3600) == nil)

        _ = timeline.normalize(pts: 0, dts: 0, duration: 3600)
        let carried = timeline.normalize(pts: nil, dts: nil, duration: 3600)
        #expect(carried == PacketTimeline.Timestamps(pts: 3600, dts: 3600))
    }

    @Test("The output-domain guard catches ticks that rescaling collapsed")
    func enforcingIncreaseInOutputTicks() {
        // Two distinct 90 kHz timestamps land on the same 48 kHz tick after
        // rescaling; the muxer rejects the second one unless it's nudged.
        let guarded = PacketTimeline.enforcingIncrease(pts: 1000, dts: 1000, after: 1000)
        #expect(guarded.dts == 1001)
        #expect(guarded.pts == 1001)

        // A timestamp that already advances is left exactly as it is.
        let untouched = PacketTimeline.enforcingIncrease(pts: 2000, dts: 1500, after: 1000)
        #expect(untouched == PacketTimeline.Timestamps(pts: 2000, dts: 1500))

        // Nothing written yet: nothing to compare against.
        let first = PacketTimeline.enforcingIncrease(pts: -1800, dts: -1800, after: nil)
        #expect(first == PacketTimeline.Timestamps(pts: -1800, dts: -1800))
    }

    @Test("Every stream shifts by the same anchor, so audio stays in sync")
    func sharedAnchorKeepsSync() {
        let anchor: Int64 = 40_000 * 90_000
        // Video's first packet is the anchor; audio's arrives 20 ms earlier in
        // the mux. Both must keep that relationship in the output.
        var video = timeline(anchor: anchor)
        var audio = timeline(anchor: anchor)

        let videoFirst = video.normalize(pts: anchor, dts: anchor, duration: 3600)
        let audioFirst = audio.normalize(pts: anchor - 1800, dts: anchor - 1800, duration: 1024)

        #expect(videoFirst!.dts == 0)
        #expect(audioFirst!.dts == -1800)
    }
}
