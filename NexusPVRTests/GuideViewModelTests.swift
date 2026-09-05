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

    @Test("previousDay does nothing when already viewing today and past dates are disallowed")
    func previousDayClampsToToday() {
        let vm = GuideViewModel()
        vm.allowsPastDates = false
        vm.previousDay()
        #expect(Calendar.current.isDateInToday(vm.selectedDate))
    }

    @Test("previousDay moves backward from today when past dates are allowed (#119)")
    func previousDayAllowsPastWhenEnabled() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        let today = vm.selectedDate
        vm.previousDay()
        #expect(vm.selectedDate < today)
        #expect(!Calendar.current.isDateInToday(vm.selectedDate))
    }

    @Test("canGoToPreviousDay mirrors allowsPastDates while on today")
    func canGoToPreviousDayReflectsFlag() {
        let vm = GuideViewModel()
        vm.allowsPastDates = false
        #expect(vm.canGoToPreviousDay == false)
        vm.allowsPastDates = true
        #expect(vm.canGoToPreviousDay)
    }

    @Test("canGoToPreviousDay is always true once past today, regardless of the flag")
    func canGoToPreviousDayTrueWhenNotToday() {
        let vm = GuideViewModel()
        vm.allowsPastDates = false
        vm.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        #expect(vm.canGoToPreviousDay)
    }

    @Test("allowsPastDates default matches the build variant (#119)")
    func allowsPastDatesDefault() {
        let vm = GuideViewModel()
        #if DISPATCHERPVR
        #expect(vm.allowsPastDates)
        #else
        #expect(!vm.allowsPastDates)
        #endif
    }

    // MARK: - Timeline anchoring (#140)

    @Test("Catch-up timelines start at midnight, so the guide must scroll to reach now")
    func catchupTimelineStartsAtMidnight() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        let midnight = Calendar.current.startOfDay(for: Date())
        #expect(vm.timelineStart == midnight)

        // The distance the guide has to travel to sit on the current
        // half-hour — zero would mean no scroll is needed, which is exactly
        // the assumption that left the guide at 00:00 (#140).
        let target = GuideScrollHelper.calculateScrollTarget(currentTime: Date())
        let offset = GuideScrollHelper.expectedScrollOffsetX(
            timelineStart: vm.timelineStart,
            scrollTarget: target,
            hourWidth: 150
        )
        #expect(offset == CGFloat(target.timeIntervalSince(midnight) / 3600) * 150)
    }

    @Test("Without catch-up the timeline already starts at the current half-hour")
    func regularTimelineStartsAtNow() {
        let vm = GuideViewModel()
        vm.allowsPastDates = false
        let target = GuideScrollHelper.calculateScrollTarget(currentTime: Date())
        #expect(vm.timelineStart == target)
        #expect(GuideScrollHelper.expectedScrollOffsetX(
            timelineStart: vm.timelineStart,
            scrollTarget: target,
            hourWidth: 150
        ) == 0)
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

    @Test("timelineStart snaps to today's current half-hour when past hours are unavailable")
    func timelineStartTodayHalfHourWithoutPastHours() {
        let vm = GuideViewModel()
        vm.allowsPastDates = false
        let start = vm.timelineStart
        let minute = Calendar.current.component(.minute, from: start)
        #expect(minute == 0 || minute == 30)
    }

    @Test("timelineStart is midnight today when catch-up permits past hours (#119)")
    func timelineStartTodayAtMidnightWithPastHours() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: vm.timelineStart)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
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

    @Test("hoursToShow includes all of today when catch-up permits past hours (#119)")
    func hoursToShowIncludesAllOfTodayForCatchup() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        #expect(vm.hoursToShow.count == 24)
        #expect(Calendar.current.component(.hour, from: vm.hoursToShow[0]) == 0)
    }

    // MARK: - Memoized timeline geometry (#141)

    @Test("Repeated timeline reads return identical geometry")
    func timelineGeometryIsStableAcrossReads() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        #expect(vm.timelineStart == vm.timelineStart)
        #expect(vm.hoursToShow == vm.hoursToShow)
        #expect(vm.hourSlotCount == vm.hoursToShow.count)
    }

    @Test("Changing the selected day recomputes the memoized timeline")
    func timelineGeometryFollowsSelectedDate() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        #expect(Calendar.current.isDateInToday(vm.timelineStart))

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        vm.selectedDate = tomorrow
        #expect(vm.timelineStart == Calendar.current.startOfDay(for: tomorrow))
        #expect(vm.hoursToShow.first == Calendar.current.startOfDay(for: tomorrow))
        #expect(vm.hourSlotCount == 24)
    }

    @Test("Changing allowsPastDates recomputes the memoized timeline")
    func timelineGeometryFollowsPastDatesFlag() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        #expect(vm.timelineStart == Calendar.current.startOfDay(for: Date()))

        vm.allowsPastDates = false
        let minute = Calendar.current.component(.minute, from: vm.timelineStart)
        #expect(minute == 0 || minute == 30)
        #expect(vm.timelineStart > Calendar.current.startOfDay(for: Date()) || minute == 0)
    }

    @Test("scrollTargetTime matches the helper and is stable across reads")
    func scrollTargetTimeIsMemoized() {
        let vm = GuideViewModel()
        let expected = GuideScrollHelper.calculateScrollTarget(currentTime: Date())
        #expect(vm.scrollTargetTime == expected)
        #expect(vm.scrollTargetTime == vm.scrollTargetTime)
    }

    @Test("hourSlotCount matches hourCount for the selected date")
    func hourSlotCountMatchesHourCount() {
        let vm = GuideViewModel()
        vm.allowsPastDates = true
        #expect(vm.hourSlotCount == GuideViewModel.hourCount(for: vm.selectedDate, includesPastHours: true))

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        vm.selectedDate = tomorrow
        #expect(vm.hourSlotCount == GuideViewModel.hourCount(for: tomorrow, includesPastHours: true))
    }

    // MARK: - hourCount

    @Test("hourCount enforces minimum 6 hours even late at night")
    func hourCountLateAtNightMinimum() {
        let calendar = Calendar.current
        let tonight11pm = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let count = GuideViewModel.hourCount(for: tonight11pm, now: tonight11pm)
        #expect(count >= 6)
    }

    @Test("hourCount returns 24 for a non-today date")
    func hourCountNonToday() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let count = GuideViewModel.hourCount(for: tomorrow, now: Date())
        #expect(count == 24)
    }

    @Test("hourCount returns 24 for today when past hours are included (#119)")
    func hourCountTodayWithPastHours() {
        let now = Date()
        let count = GuideViewModel.hourCount(for: now, now: now, includesPastHours: true)
        #expect(count == 24)
    }

    @Test("Guide grid width at 23:00 is usable on macOS (minimum 1800pt)")
    func guideGridWidthAt11pm() {
        let calendar = Calendar.current
        let hourWidth: CGFloat = Theme.hourColumnWidth   // 300pt (non-tvOS)
        let channelWidth: CGFloat = Theme.channelColumnWidth // 72pt

        // Test every hour from 20:00 to 23:30
        let testTimes: [(hour: Int, minute: Int)] = [
            (20, 0), (21, 0), (22, 0), (23, 0), (23, 30)
        ]
        for time in testTimes {
            let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date())!
            let count = GuideViewModel.hourCount(for: date, now: date)
            let gridWidth = channelWidth + hourWidth * CGFloat(count)
            // Minimum usable macOS window width ~1200pt; grid should be at least 1800pt
            #expect(gridWidth >= 1800, "Grid too narrow at \(time.hour):\(time.minute) — \(gridWidth)pt from \(count) hours")
        }
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

    // MARK: - refresh

    @Test("refresh is a no-op when no EPGCache is attached")
    func refreshWithoutCache() async {
        let vm = GuideViewModel()
        await vm.refresh(using: PVRClient(config: ServerConfig(host: "demo", pin: "", useHTTPS: false)))
        #expect(vm.error == nil)
        #expect(vm.hasLoaded == false)
    }

    @Test("refresh keeps cached channels when the server is not configured")
    func refreshUnconfigured() async {
        let vm = GuideViewModel()
        let cache = EPGCache()
        cache.visibleChannels = [Channel(id: 1, name: "A", number: 1)]
        vm.epgCache = cache

        await vm.refresh(using: PVRClient(config: ServerConfig(host: "", pin: "", useHTTPS: false)))

        #expect(vm.channels.count == 1)
    }

    // MARK: - Group filtering (#158)

    @Test("Selecting a group narrows the guide to that group's channels")
    func groupFilterNarrowsChannels() {
        let sports = ChannelGroup(name: "Sports")
        let news = ChannelGroup(name: "News")
        let cache = EPGCache()
        cache.visibleChannels = [
            Channel(id: 1, name: "Sports One", number: 1, groupIds: [sports.id]),
            Channel(id: 2, name: "Both", number: 2, groupIds: [sports.id, news.id]),
            Channel(id: 3, name: "News One", number: 3, groupIds: [news.id])
        ]
        let vm = GuideViewModel()
        vm.epgCache = cache

        vm.selectedGroupId = sports.id
        #expect(vm.hasActiveFilters)
        #expect(vm.channels.map(\.id) == [1, 2])

        vm.selectedGroupId = news.id
        #expect(vm.channels.map(\.id) == [2, 3])
    }

    @Test("Clearing the group filter restores every channel")
    func clearingGroupFilterRestoresAllChannels() {
        let sports = ChannelGroup(name: "Sports")
        let cache = EPGCache()
        cache.visibleChannels = [
            Channel(id: 1, name: "Sports One", number: 1, groupIds: [sports.id]),
            Channel(id: 2, name: "Ungrouped", number: 2)
        ]
        let vm = GuideViewModel()
        vm.epgCache = cache

        vm.selectedGroupId = sports.id
        #expect(vm.channels.count == 1)

        vm.selectedGroupId = nil
        #expect(vm.hasActiveFilters == false)
        #expect(vm.channels.count == 2)
    }

    @Test("A group with no channels shows an empty guide rather than everything")
    func emptyGroupShowsNoChannels() {
        let empty = ChannelGroup(name: "Empty")
        let cache = EPGCache()
        cache.visibleChannels = [Channel(id: 1, name: "A", number: 1)]
        let vm = GuideViewModel()
        vm.epgCache = cache

        vm.selectedGroupId = empty.id
        #expect(vm.channels.isEmpty)
    }

    @Test("Channel search applies on top of the group filter")
    func searchCombinesWithGroupFilter() {
        let sports = ChannelGroup(name: "Sports")
        let cache = EPGCache()
        cache.visibleChannels = [
            Channel(id: 1, name: "Hockey", number: 1, groupIds: [sports.id]),
            Channel(id: 2, name: "Soccer", number: 2, groupIds: [sports.id]),
            Channel(id: 3, name: "Hockey Classics", number: 3)
        ]
        let vm = GuideViewModel()
        vm.epgCache = cache
        vm.selectedGroupId = sports.id
        vm.channelSearchText = "hockey"

        #expect(vm.channels.map(\.id) == [1])
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
