//
//  EPGDayWindows.swift
//  PVR Client
//
//  Calendar-day windows the EPG cache loads one request at a time (#157).
//

import Foundation

nonisolated enum EPGDayWindows {
    /// The calendar day containing `date`, midnight to midnight.
    static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 3600)
        return DateInterval(start: start, end: end)
    }

    /// Days to preload around `now`, nearest first: today, tomorrow, the days
    /// back to `daysBack`, then the rest of the days out to `daysForward`.
    static func preloadOrder(
        now: Date,
        daysBack: Int,
        daysForward: Int,
        calendar: Calendar = .current
    ) -> [DateInterval] {
        var offsets = [0]
        if daysForward >= 1 { offsets.append(1) }
        if daysBack >= 1 { offsets.append(contentsOf: (1...daysBack).map { -$0 }) }
        if daysForward >= 2 { offsets.append(contentsOf: 2...daysForward) }

        let today = calendar.startOfDay(for: now)
        return offsets.compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
                .map { day(containing: $0, calendar: calendar) }
        }
    }

    /// Every day from the one containing `start` through the one containing
    /// `end`, oldest first. Empty when `end` falls on an earlier day.
    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [DateInterval] {
        var result: [DateInterval] = []
        var current = day(containing: start, calendar: calendar)
        let last = day(containing: end, calendar: calendar)
        while current.start <= last.start {
            result.append(current)
            current = day(containing: current.end, calendar: calendar)
        }
        return result
    }
}
