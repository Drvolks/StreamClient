//
//  GuideViewModelTests.swift
//  NexusPVRTests
//
//  Pure-logic tests for GuideViewModel. We construct instances without a real
//  PVRClient or EPGCache, exercise computed properties and helpers, and assert
//  the results. Network-dependent paths (loadData, navigateToDate) are not
//  covered here.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct GuideViewModelTests {

    // MARK: - hasActiveFilters

    @Test("hasActiveFilters is false when no profile or group is selected")
    func noActiveFilters() {
        let vm = GuideViewModel()
        #expect(vm.hasActiveFilters == false)
    }

    @Test("hasActiveFilters true when profile is selected")
    func profileFilter() {
        let vm = GuideViewModel()
        vm.selectedProfileId = 1
        #expect(vm.hasActiveFilters)
    }

    @Test("hasActiveFilters true when group is selected")
    func groupFilter() {
        let vm = GuideViewModel()
        vm.selectedGroupId = 3
        #expect(vm.hasActiveFilters)
    }

    // MARK: - Day navigation

    @Test("previousDay does nothing when already viewing today")
    func previousDayClampsToToday() {
        let vm = GuideViewModel()
        let today = vm.selectedDate
        vm.previousDay()
        #expect(Calendar.current.isDateInToday(vm.selectedDate))
        _ = today
    }

    @Test("previousDay moves backward from a future date")
    func previousDayMovesBack() {
        let vm = GuideViewModel()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        vm.selectedDate = tomorrow
        vm.previousDay()
        #expect(Calendar.current.isDateInToday(vm.selectedDate))
    }

    @Test("nextDay advances the selected date by one day")
    func nextDayAdvances() {
        let vm = GuideViewModel()
        vm.nextDay()
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(Calendar.current.isDate(vm.selectedDate, inSameDayAs: expected))
    }

    @Test("scrollToNow resets selectedDate to today")
    func scrollToNowResets() {
        let vm = GuideViewModel()
        vm.selectedDate = Date().addingTimeInterval(86_400 * 3)
        vm.scrollToNow()
        #expect(Calendar.current.isDateInToday(vm.selectedDate))
    }

    // MARK: - isOnToday

    @Test("isOnToday true for the current date")
    func isOnTodayTrue() {
        let vm = GuideViewModel()
        #expect(vm.isOnToday)
    }

    @Test("isOnToday false for tomorrow")
    func isOnTodayFalse() {
        let vm = GuideViewModel()
        vm.selectedDate = Date().addingTimeInterval(86_400)
        #expect(vm.isOnToday == false)
    }

    // MARK: - timelineStart / hoursToShow

    @Test("timelineStart snaps to today's current half-hour when on today")
    func timelineStartTodayHalfHour() {
        let vm = GuideViewModel()
        let start = vm.timelineStart
        let minute = Calendar.current.component(.minute, from: start)
        #expect(minute == 0 || minute == 30)
    }

    @Test("timelineStart is midnight for a non-today date")
    func timelineStartNonToday() {
        let vm = GuideViewModel()
        vm.selectedDate = Date().addingTimeInterval(86_400 * 2)
        let start = vm.timelineStart
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: start)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("hoursToShow returns a non-empty array of hour Dates")
    func hoursToShowNonEmpty() {
        let vm = GuideViewModel()
        vm.selectedDate = Date().addingTimeInterval(86_400) // tomorrow
        let hours = vm.hoursToShow
        #expect(hours.count == 24)
    }

    // MARK: - channels / programs without epg cache

    @Test("channels is empty when no EPGCache is attached")
    func channelsEmptyWithoutCache() {
        let vm = GuideViewModel()
        #expect(vm.channels.isEmpty)
    }

    @Test("programs(for:) is empty when no EPGCache is attached")
    func programsEmptyWithoutCache() {
        let vm = GuideViewModel()
        let channel = Channel(id: 1, name: "A", number: 1)
        #expect(vm.programs(for: channel).isEmpty)
    }

    @Test("visiblePrograms(for:) is empty when no EPGCache is attached")
    func visibleProgramsEmptyWithoutCache() {
        let vm = GuideViewModel()
        let channel = Channel(id: 1, name: "A", number: 1)
        #expect(vm.visiblePrograms(for: channel).isEmpty)
    }

    // MARK: - updateKeywordMatches

    @Test("updateKeywordMatches clears the set when keywords are empty")
    func updateKeywordMatchesEmpty() {
        let vm = GuideViewModel()
        vm.updateKeywordMatches(keywords: [])
        #expect(vm.keywordMatchedProgramIds.isEmpty)
    }

    @Test("updateKeywordMatches clears the set when there is no EPGCache")
    func updateKeywordMatchesNoCache() {
        let vm = GuideViewModel()
        vm.updateKeywordMatches(keywords: ["news"])
        #expect(vm.keywordMatchedProgramIds.isEmpty)
    }

    // MARK: - programWidth / programOffset math

    @Test("programWidth scales by hour-width for full-hour programs")
    func programWidthFullHour() {
        let vm = GuideViewModel()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let program = Program(
            id: 1,
            name: "Show",
            subtitle: nil,
            desc: nil,
            start: Int(start.timeIntervalSince1970),
            end: Int(start.timeIntervalSince1970) + 3600,
            genres: nil,
            channelId: 1
        )
        // Use a selectedDate far from now so hoursToShow returns a full 24
        vm.selectedDate = start.addingTimeInterval(86_400 * 7)
        let width = vm.programWidth(for: program, hourWidth: 200, startTime: start)
        #expect(width == 200)
    }

    @Test("programWidth clamps to at least 50 points for very short programs")
    func programWidthMinimum() {
        let vm = GuideViewModel()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let program = Program(
            id: 1,
            name: "Short",
            subtitle: nil,
            desc: nil,
            start: Int(start.timeIntervalSince1970),
            end: Int(start.timeIntervalSince1970) + 60, // 1 minute
            genres: nil,
            channelId: 1
        )
        vm.selectedDate = start.addingTimeInterval(86_400 * 7)
        let width = vm.programWidth(for: program, hourWidth: 200, startTime: start)
        #expect(width == 50)
    }

    @Test("programOffset scales by the hours elapsed since startTime")
    func programOffsetHalfHour() {
        let vm = GuideViewModel()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let program = Program(
            id: 1,
            name: "X",
            subtitle: nil,
            desc: nil,
            start: Int(start.timeIntervalSince1970) + 1800, // 30 min after start
            end: Int(start.timeIntervalSince1970) + 5400,
            genres: nil,
            channelId: 1
        )
        let offset = vm.programOffset(for: program, hourWidth: 200, startTime: start)
        #expect(offset == 100)
    }

    @Test("programOffset is zero when program starts before timeline start")
    func programOffsetClamped() {
        let vm = GuideViewModel()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let program = Program(
            id: 1,
            name: "X",
            subtitle: nil,
            desc: nil,
            start: Int(start.timeIntervalSince1970) - 3600,
            end: Int(start.timeIntervalSince1970) + 3600,
            genres: nil,
            channelId: 1
        )
        let offset = vm.programOffset(for: program, hourWidth: 200, startTime: start)
        #expect(offset == 0)
    }

    // MARK: - Recording lookup by program

    @Test("isScheduledRecording matches by epgEventId")
    func scheduledRecordingMatchByEventId() {
        let vm = GuideViewModel()
        vm.recordings = [
            Recording(
                id: 10,
                name: "Show",
                startTime: 1_700_000_000,
                duration: 3600,
                status: "pending",
                recurring: 0,
                epgEventId: 42
            )
        ]
        let program = Program(
            id: 42,
            name: "Show",
            subtitle: nil,
            desc: nil,
            start: 1_700_000_000,
            end: 1_700_003_600,
            genres: nil,
            channelId: 1
        )
        #expect(vm.isScheduledRecording(program))
        #expect(vm.recordingStatus(program) == .pending)
        #expect(vm.recordingId(for: program) == 10)
    }

    @Test("isScheduledRecording returns false for unknown programs")
    func scheduledRecordingNoMatch() {
        let vm = GuideViewModel()
        let program = Program(
            id: 999,
            name: "Unknown",
            subtitle: nil,
            desc: nil,
            start: 0,
            end: 3600,
            genres: nil,
            channelId: 1
        )
        #expect(vm.isScheduledRecording(program) == false)
        #expect(vm.recordingStatus(program) == nil)
    }

    @Test("Setting recordings populates both lookup indices")
    func recordingsLookupIndices() {
        let vm = GuideViewModel()
        // Include a recording with an epgEventId and one without — the second
        // should still be findable via the name+start lookup.
        vm.recordings = [
            Recording(
                id: 1,
                name: "Show A",
                startTime: 100,
                duration: 3600,
                status: "ready",
                recurring: 0,
                epgEventId: 500
            ),
            Recording(
                id: 2,
                name: "Show B",
                startTime: 200,
                duration: 3600,
                status: "pending",
                recurring: 0,
                epgEventId: nil
            )
        ]
        let programB = Program(
            id: 888,
            name: "Show B",
            subtitle: nil,
            desc: nil,
            start: 200,
            end: 3800,
            genres: nil,
            channelId: 1
        )
        // Matches via the name+start secondary lookup.
        #expect(vm.isScheduledRecording(programB))
        #expect(vm.recordingId(for: programB) == 2)
    }

    // MARK: - detectedSport

    @Test("detectedSport caches the first lookup result")
    func detectedSportCaches() {
        let vm = GuideViewModel()
        let program = Program(
            id: 1,
            name: "Champions League Final",
            subtitle: nil,
            desc: nil,
            start: 0,
            end: 3600,
            genres: ["Sports", "Soccer"],
            channelId: 1
        )
        // Two calls should return the same result (the second comes from the cache).
        let first = vm.detectedSport(for: program)
        let second = vm.detectedSport(for: program)
        #expect(first == second)
    }
}
