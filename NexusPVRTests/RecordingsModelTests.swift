//
//  RecordingsModelTests.swift
//  NexusPVRTests
//
//  Tests for RecordingsSeriesSummary and recording-related model logic.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct RecordingsModelTests {

    private func rec(id: Int, name: String, status: RecordingStatus, playbackPosition: Int? = nil, duration: Int? = nil) -> Recording {
        Recording(id: id, name: name, startTime: 0, duration: duration, status: status.rawValue, playbackPosition: playbackPosition)
    }

    // MARK: - RecordingsSeriesSummary

    @Test("RecordingsSeriesSummary id equals name")
    func summaryId() {
        let summary = RecordingsSeriesSummary(name: "Test", active: [], completed: [], scheduled: [], bannerURL: nil)
        #expect(summary.id == "Test")
    }

    @Test("RecordingsSeriesSummary totalCount sums all categories")
    func summaryTotalCount() {
        let summary = RecordingsSeriesSummary(
            name: "Show",
            active: [rec(id: 1, name: "E1", status: .recording)],
            completed: [rec(id: 2, name: "E2", status: .ready), rec(id: 3, name: "E3", status: .ready)],
            scheduled: [rec(id: 4, name: "E4", status: .pending)],
            bannerURL: nil
        )
        #expect(summary.totalCount == 4)
    }

    @Test("RecordingsSeriesSummary unwatchedCount counts unwatched completed")
    func summaryUnwatchedCount() {
        let watched = rec(id: 1, name: "W", status: .ready, playbackPosition: 3600, duration: 3600)
        let unwatched = rec(id: 2, name: "U", status: .ready, playbackPosition: nil, duration: nil)
        let summary = RecordingsSeriesSummary(
            name: "Show",
            active: [],
            completed: [watched, unwatched],
            scheduled: [],
            bannerURL: nil
        )
        #expect(summary.unwatchedCount == 1)
    }

    @Test("RecordingsSeriesSummary bannerURL stored")
    func summaryBannerURL() {
        let summary = RecordingsSeriesSummary(
            name: "Show",
            active: [],
            completed: [],
            scheduled: [],
            bannerURL: "http://example.com/banner.jpg"
        )
        #expect(summary.bannerURL == "http://example.com/banner.jpg")
    }

    @Test("RecordingsSeriesSummary bannerURL nil")
    func summaryBannerURLNil() {
        let summary = RecordingsSeriesSummary(name: "Show", active: [], completed: [], scheduled: [], bannerURL: nil)
        #expect(summary.bannerURL == nil)
    }

    // MARK: - Recording.playbackPosition

    @Test("Recording playbackPosition defaults to nil")
    func recordingPlaybackDefaults() {
        let r = Recording(id: 1, name: "Test", startTime: 0)
        #expect(r.playbackPosition == nil)
    }

    @Test("Recording isWatched true when playback past 90%")
    func recordingIsWatchedTrue() {
        let r = Recording(id: 1, name: "Test", startTime: 0, duration: 3600, playbackPosition: 3500)
        #expect(r.isWatched == true)
    }

    @Test("Recording isWatched false when playback less than 90%")
    func recordingIsWatchedFalse() {
        let r = Recording(id: 1, name: "Test", startTime: 0, duration: 3600, playbackPosition: 1000)
        #expect(r.isWatched == false)
    }

    @Test("Recording isWatched false when no playback position")
    func recordingIsWatchedFalseNoPosition() {
        let r = Recording(id: 1, name: "Test", startTime: 0, duration: 3600)
        #expect(r.isWatched == false)
    }

    @Test("Recording hasResumePosition true when position > 10")
    func recordingHasResumePosition() {
        let r = Recording(id: 1, name: "Test", startTime: 0, playbackPosition: 120)
        #expect(r.hasResumePosition == true)
    }

    @Test("Recording hasResumePosition false when position nil")
    func recordingHasResumePositionFalse() {
        let r = Recording(id: 1, name: "Test", startTime: 0)
        #expect(r.hasResumePosition == false)
    }

    // MARK: - Recording computed properties

    @Test("Recording recordingStatus maps status string")
    func recordingStatusMapping() {
        let readyRec = Recording(id: 1, name: "Test", startTime: 0, status: "ready")
        #expect(readyRec.recordingStatus == .ready)

        let recordingRec = Recording(id: 2, name: "Test", startTime: 0, status: "recording")
        #expect(recordingRec.recordingStatus == .recording)
    }
}
