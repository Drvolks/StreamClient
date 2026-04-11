//
//  RecordingStatusTests.swift
//  NexusPVRTests
//
//  Tests for RecordingStatus enum semantics.
//

import Testing
@testable import NextPVR

struct RecordingStatusTests {

    @Test("displayName maps each case to its label")
    func displayName() {
        #expect(RecordingStatus.pending.displayName == "Scheduled")
        #expect(RecordingStatus.recording.displayName == "Recording")
        #expect(RecordingStatus.ready.displayName == "Completed")
        #expect(RecordingStatus.failed.displayName == "Failed")
        #expect(RecordingStatus.conflict.displayName == "Conflict")
        #expect(RecordingStatus.deleted.displayName == "Deleted")
    }

    @Test("isCompleted is true only for .ready")
    func isCompleted() {
        #expect(RecordingStatus.ready.isCompleted)
        #expect(RecordingStatus.pending.isCompleted == false)
        #expect(RecordingStatus.recording.isCompleted == false)
        #expect(RecordingStatus.failed.isCompleted == false)
        #expect(RecordingStatus.conflict.isCompleted == false)
        #expect(RecordingStatus.deleted.isCompleted == false)
    }

    @Test("isPlayable is true for .ready and .recording")
    func isPlayable() {
        #expect(RecordingStatus.ready.isPlayable)
        #expect(RecordingStatus.recording.isPlayable)
        #expect(RecordingStatus.pending.isPlayable == false)
        #expect(RecordingStatus.failed.isPlayable == false)
        #expect(RecordingStatus.conflict.isPlayable == false)
        #expect(RecordingStatus.deleted.isPlayable == false)
    }

    @Test("isScheduled is true only for .pending")
    func isScheduled() {
        #expect(RecordingStatus.pending.isScheduled)
        #expect(RecordingStatus.recording.isScheduled == false)
        #expect(RecordingStatus.ready.isScheduled == false)
    }

    @Test("RecordingStatus raw values round-trip via init")
    func rawValueInit() {
        #expect(RecordingStatus(rawValue: "pending") == .pending)
        #expect(RecordingStatus(rawValue: "recording") == .recording)
        #expect(RecordingStatus(rawValue: "ready") == .ready)
        #expect(RecordingStatus(rawValue: "failed") == .failed)
        #expect(RecordingStatus(rawValue: "conflict") == .conflict)
        #expect(RecordingStatus(rawValue: "deleted") == .deleted)
        #expect(RecordingStatus(rawValue: "Ready") == nil) // case-sensitive
        #expect(RecordingStatus(rawValue: "") == nil)
    }
}
