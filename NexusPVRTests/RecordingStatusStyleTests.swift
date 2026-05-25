//
//  RecordingStatusStyleTests.swift
//  NexusPVRTests
//
//  Tests for RecordingStatus+Style extension: statusColor, statusIcon.
//

import Testing
import SwiftUI
@testable import NextPVR

@MainActor
struct RecordingStatusStyleTests {

    @Test("statusColor returns non-clear colors for all statuses")
    func statusColorNonClear() {
        let statuses: [RecordingStatus] = [.pending, .recording, .ready, .failed, .conflict, .deleted]
        for s in statuses {
            #expect(s.statusColor != Color.clear)
        }
    }

    @Test("statusColor returns Theme colors — pending = warning")
    func pendingStatusColor() {
        #expect(RecordingStatus.pending.statusColor == Theme.warning)
    }

    @Test("statusColor returns Theme colors — recording = recording")
    func recordingStatusColor() {
        #expect(RecordingStatus.recording.statusColor == Theme.recording)
    }

    @Test("statusColor returns Theme colors — ready = success")
    func readyStatusColor() {
        #expect(RecordingStatus.ready.statusColor == Theme.success)
    }

    @Test("statusColor returns Theme colors — failed = error")
    func failedStatusColor() {
        #expect(RecordingStatus.failed.statusColor == Theme.error)
    }

    @Test("statusColor returns Theme colors — conflict = warning")
    func conflictStatusColor() {
        #expect(RecordingStatus.conflict.statusColor == Theme.warning)
    }

    @Test("statusColor returns Theme colors — deleted = error")
    func deletedStatusColor() {
        #expect(RecordingStatus.deleted.statusColor == Theme.error)
    }

    @Test("statusIcon returns non-empty SF Symbol for all statuses")
    func statusIconNonEmpty() {
        let statuses: [RecordingStatus] = [.pending, .recording, .ready, .failed, .conflict, .deleted]
        for s in statuses {
            #expect(!s.statusIcon.isEmpty)
        }
    }

    @Test("statusIcon returns expected symbols")
    func statusIconExpected() {
        #expect(RecordingStatus.pending.statusIcon == "clock")
        #expect(RecordingStatus.recording.statusIcon == "record.circle")
        #expect(RecordingStatus.ready.statusIcon == "checkmark.circle")
        #expect(RecordingStatus.failed.statusIcon == "xmark.circle")
        #expect(RecordingStatus.conflict.statusIcon == "exclamationmark.triangle")
        #expect(RecordingStatus.deleted.statusIcon == "trash")
    }
}
