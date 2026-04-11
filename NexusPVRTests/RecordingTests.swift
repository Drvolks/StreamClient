//
//  RecordingTests.swift
//  NexusPVRTests
//
//  Tests for Recording computed properties.
//

import Testing
import Foundation
@testable import NextPVR

struct RecordingTests {

    private func recording(
        id: Int = 1,
        name: String = "Show",
        subtitle: String? = nil,
        desc: String? = nil,
        startTime: Int? = 1000,
        duration: Int? = 3600,
        status: String? = nil,
        playbackPosition: Int? = nil,
        prePadding: Int? = nil,
        postPadding: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        size: Int64? = nil
    ) -> Recording {
        Recording(
            id: id,
            name: name,
            subtitle: subtitle,
            desc: desc,
            startTime: startTime,
            duration: duration,
            channel: "CH1",
            channelId: 1,
            status: status,
            file: nil,
            recurring: 0,
            recurringParent: nil,
            epgEventId: nil,
            size: size,
            quality: nil,
            genres: nil,
            playbackPosition: playbackPosition,
            prePadding: prePadding,
            postPadding: postPadding,
            season: season,
            episode: episode
        )
    }

    // MARK: - Duration / padding

    @Test("durationMinutes converts seconds to whole minutes")
    func durationMinutes() {
        #expect(recording(duration: 3600).durationMinutes == 60)
        #expect(recording(duration: nil).durationMinutes == nil)
    }

    @Test("totalRecordingDuration includes pre and post padding")
    func totalRecordingDuration_withPadding() {
        let r = recording(duration: 3600, prePadding: 5, postPadding: 2)
        #expect(r.totalRecordingDuration == 3600 + 300 + 120)
    }

    @Test("totalRecordingDuration treats missing padding as zero")
    func totalRecordingDuration_noPadding() {
        let r = recording(duration: 1800)
        #expect(r.totalRecordingDuration == 1800)
    }

    @Test("totalRecordingDuration is nil when duration is nil")
    func totalRecordingDuration_nilDuration() {
        #expect(recording(duration: nil).totalRecordingDuration == nil)
    }

    @Test("recordingStartTime subtracts pre-padding")
    func recordingStartTime_subtractsPrePadding() {
        let r = recording(startTime: 1000, prePadding: 5)
        #expect(r.recordingStartTime == 1000 - 300)
    }

    @Test("recordingStartTime equals startTime when no prePadding")
    func recordingStartTime_noPadding() {
        #expect(recording(startTime: 1000).recordingStartTime == 1000)
    }

    // MARK: - Watched / resume

    @Test("isWatched is true when position >= 90% of duration")
    func isWatched_true() {
        let r = recording(duration: 100, playbackPosition: 90)
        #expect(r.isWatched)
    }

    @Test("isWatched is false just below 90%")
    func isWatched_belowThreshold() {
        let r = recording(duration: 100, playbackPosition: 89)
        #expect(r.isWatched == false)
    }

    @Test("isWatched is false when no playback position")
    func isWatched_noPosition() {
        #expect(recording(duration: 100, playbackPosition: nil).isWatched == false)
    }

    @Test("isWatched is false when duration is zero")
    func isWatched_zeroDuration() {
        let r = recording(duration: 0, playbackPosition: 10)
        #expect(r.isWatched == false)
    }

    @Test("hasResumePosition ignores trivial positions under 10 seconds")
    func hasResumePosition_trivial() {
        #expect(recording(playbackPosition: 5).hasResumePosition == false)
        #expect(recording(playbackPosition: 10).hasResumePosition == false)
    }

    @Test("hasResumePosition true for non-trivial positions")
    func hasResumePosition_true() {
        #expect(recording(playbackPosition: 120).hasResumePosition)
    }

    @Test("hasResumePosition false when position is nil")
    func hasResumePosition_nil() {
        #expect(recording(playbackPosition: nil).hasResumePosition == false)
    }

    // MARK: - recordingStatus

    @Test("recordingStatus defaults to .pending when status missing")
    func recordingStatus_default() {
        #expect(recording(status: nil).recordingStatus == .pending)
    }

    @Test("recordingStatus parses lowercased string")
    func recordingStatus_parse() {
        #expect(recording(status: "ready").recordingStatus == .ready)
        #expect(recording(status: "recording").recordingStatus == .recording)
        #expect(recording(status: "failed").recordingStatus == .failed)
    }

    @Test("recordingStatus handles mixed case by lowercasing")
    func recordingStatus_mixedCase() {
        #expect(recording(status: "Ready").recordingStatus == .ready)
        #expect(recording(status: "PENDING").recordingStatus == .pending)
    }

    @Test("recordingStatus falls back to .pending for unknown string")
    func recordingStatus_unknown() {
        #expect(recording(status: "weird-state").recordingStatus == .pending)
    }

    // MARK: - Dates

    @Test("startDate and endDate are computed from startTime + duration")
    func dates_computed() {
        let r = recording(startTime: 1000, duration: 3600)
        #expect(r.startDate == Date(timeIntervalSince1970: 1000))
        #expect(r.endDate == Date(timeIntervalSince1970: 4600))
    }

    @Test("startDate is nil when startTime missing")
    func startDate_nil() {
        #expect(recording(startTime: nil).startDate == nil)
    }

    @Test("endDate is nil when either startTime or duration is missing")
    func endDate_nil() {
        #expect(recording(startTime: 1000, duration: nil).endDate == nil)
        #expect(recording(startTime: nil, duration: 3600).endDate == nil)
    }

    // MARK: - File size

    @Test("fileSizeFormatted returns a non-empty string for valid size")
    func fileSizeFormatted_withSize() {
        let r = recording(size: 1_500_000_000)
        #expect(r.fileSizeFormatted?.isEmpty == false)
    }

    @Test("fileSizeFormatted is nil when size is nil")
    func fileSizeFormatted_nil() {
        #expect(recording(size: nil).fileSizeFormatted == nil)
    }

    // MARK: - cleanName / isNew

    @Test("cleanName strips unicode New marker")
    func cleanName_strip() {
        let r = recording(name: "Sample Show \u{1D3A}\u{1D49}\u{02B7}")
        #expect(r.cleanName == "Sample Show")
        #expect(r.isNew)
    }

    // MARK: - seriesInfo

    @Test("seriesInfo uses explicit season/episode when positive")
    func seriesInfo_explicit() {
        let r = recording(name: "Show", season: 2, episode: 5)
        #expect(r.seriesInfo?.season == 2)
        #expect(r.seriesInfo?.episode == 5)
    }

    @Test("seriesInfo falls back to subtitle pattern parse")
    func seriesInfo_parsed() {
        let r = recording(name: "Show", subtitle: "S04E12")
        #expect(r.seriesInfo?.season == 4)
        #expect(r.seriesInfo?.episode == 12)
    }

    @Test("seriesInfo is nil when season/episode are zero")
    func seriesInfo_zeroExplicit() {
        let r = recording(name: "Show", season: 0, episode: 0)
        #expect(r.seriesInfo == nil)
    }
}
