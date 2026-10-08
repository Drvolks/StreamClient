//
//  TopicDaySectionTests.swift
//  NexusPVRTests
//

import Foundation
import Testing
@testable import NextPVR

struct TopicDaySectionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let us = Locale(identifier: "en_US")

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func item(_ id: Int, day: Int, hour: Int) -> MatchingProgram {
        let start = Int(date(day: day, hour: hour).timeIntervalSince1970)
        let program = Program(id: id, name: "P\(id)", subtitle: nil, desc: nil, start: start, end: start + 3600, genres: nil, channelId: 1)
        return MatchingProgram(program: program, channel: Channel(id: 1, name: "One", number: 1), matchedKeyword: "Cycling")
    }

    @Test("Groups by start day in order, titling today and tomorrow")
    func groupsByDay() {
        let now = date(day: 8, hour: 14)
        let sections = TopicDaySection.grouped(
            [item(1, day: 8, hour: 15), item(2, day: 8, hour: 22), item(3, day: 9, hour: 6), item(4, day: 10, hour: 9)],
            now: now, calendar: calendar, locale: us
        )
        #expect(sections.map(\.title) == ["Today", "Tomorrow", "Sat, Oct 10"])
        #expect(sections.map { $0.programs.map(\.program.id) } == [[1, 2], [3], [4]])
    }

    @Test("No programs, no sections")
    func empty() {
        #expect(TopicDaySection.grouped([], now: date(day: 8, hour: 14), calendar: calendar, locale: us).isEmpty)
    }
}
