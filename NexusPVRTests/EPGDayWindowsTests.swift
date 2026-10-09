//
//  EPGDayWindowsTests.swift
//  NexusPVRTests
//
//  Tests for the calendar-day windows the EPG cache loads (#157).
//

import Testing
import Foundation
@testable import NextPVR

struct EPGDayWindowsTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var toronto: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    /// 2026-02-14T15:30:00Z
    private let afternoon = Date(timeIntervalSince1970: 1_771_083_000)
    private let midnight = Date(timeIntervalSince1970: 1_771_027_200)
    private let day: TimeInterval = 24 * 3600

    @Test("A day runs from local midnight to the next")
    func dayContainingDate() {
        let window = EPGDayWindows.day(containing: afternoon, calendar: utc)
        #expect(window.start == midnight)
        #expect(window.end == midnight.addingTimeInterval(day))
    }

    @Test("Days follow the calendar's time zone, not UTC")
    func dayUsesCalendarTimeZone() {
        let window = EPGDayWindows.day(containing: afternoon, calendar: toronto)
        #expect(window.start == midnight.addingTimeInterval(5 * 3600))
        #expect(window.duration == day)
    }

    @Test("A day shortened by daylight saving still ends at the next midnight")
    func springForwardDay() throws {
        // 2026-03-08 in Toronto loses an hour.
        let noon = try #require(toronto.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let window = EPGDayWindows.day(containing: noon, calendar: toronto)
        #expect(window.duration == 23 * 3600)
        #expect(toronto.component(.hour, from: window.end) == 0)
    }

    @Test("Preload starts with today, then tomorrow, the past, and the days further out")
    func preloadOrder() {
        let windows = EPGDayWindows.preloadOrder(now: afternoon, daysBack: 2, daysForward: 4, calendar: utc)
        let offsets = windows.map { Int($0.start.timeIntervalSince(midnight) / day) }
        #expect(offsets == [0, 1, -1, -2, 2, 3, 4])
        #expect(windows.allSatisfy { $0.duration == day })
    }

    @Test("Preload with no reach is just today")
    func preloadTodayOnly() {
        let windows = EPGDayWindows.preloadOrder(now: afternoon, daysBack: 0, daysForward: 0, calendar: utc)
        #expect(windows == [EPGDayWindows.day(containing: afternoon, calendar: utc)])
    }

    @Test("A range covers every day from its first through its last, oldest first")
    func daysInRange() {
        let windows = EPGDayWindows.days(
            from: afternoon.addingTimeInterval(-3 * day),
            through: afternoon,
            calendar: utc
        )
        #expect(windows.count == 4)
        #expect(windows.first?.start == midnight.addingTimeInterval(-3 * day))
        #expect(windows.last?.start == midnight)
        #expect(zip(windows, windows.dropFirst()).allSatisfy { $0.end == $1.start })
    }

    @Test("A range within one day is that day, and a backwards range is empty")
    func degenerateRanges() {
        #expect(EPGDayWindows.days(from: midnight, through: afternoon, calendar: utc).count == 1)
        #expect(EPGDayWindows.days(from: afternoon, through: afternoon.addingTimeInterval(-day), calendar: utc).isEmpty)
    }
}
