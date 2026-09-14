//
//  MPVRecordingMonitorTests.swift
//  NexusPVRTests
//

import Testing
import Foundation
#if DISPATCHERPVR
@testable import DispatcherPVR
#else
@testable import NextPVR
#endif

struct MPVRecordingMonitorTests {

    @Test("Initializes estimated duration from recordingStartTime for HLS")
    func testHLSInitialDurationFromStartTime() {
        let monitor = MPVRecordingMonitor()
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        monitor.recordingStartTime = twoHoursAgo
        monitor.start(mpv: OpaquePointer(bitPattern: 1)!, url: "http://example.com/api/channels/recordings/1/hls/index.m3u8")

        #expect(monitor.estimatedDuration >= 7199)
        #expect(monitor.estimatedDuration <= 7205)
    }

    @Test("Updates baseline for HLS recording incorporating elapsed time")
    func testHLSUpdateBaseline() {
        let monitor = MPVRecordingMonitor()
        let ninetyMinsAgo = Date().addingTimeInterval(-5400)
        monitor.recordingStartTime = ninetyMinsAgo
        monitor.start(mpv: OpaquePointer(bitPattern: 1)!, url: "http://example.com/api/channels/recordings/1/hls/index.m3u8")

        // When mpv reports only a small 60s window:
        monitor.updateBaseline(duration: 60)

        // Estimated duration should reflect the full 5400s elapsed recording, not be clamped to 60s
        #expect(monitor.estimatedDuration >= 5399)
    }

    @Test("Stop resets monitor state")
    func testStopResetsState() {
        let monitor = MPVRecordingMonitor()
        monitor.recordingStartTime = Date().addingTimeInterval(-3600)
        monitor.start(mpv: OpaquePointer(bitPattern: 1)!, url: "http://example.com/test.m3u8")
        #expect(monitor.estimatedDuration > 0)

        monitor.stop()
        #expect(monitor.estimatedDuration == 0)
        #expect(monitor.currentURL == nil)
        #expect(monitor.recordingStartTime == nil)
    }
}
