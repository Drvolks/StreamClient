//
//  TopicDaySection.swift
//  nextpvr-apple-client
//
//  One day of topic matches in the macOS Topics list (Midnight redesign).
//

import Foundation

nonisolated struct TopicDaySection: Identifiable {
    let day: Date
    let title: String
    let programs: [MatchingProgram]

    var id: Date { day }

    /// Groups `programs` by the calendar day they start on, keeping their
    /// order, and titles each day "Today", "Tomorrow" or with its date.
    static func grouped(
        _ programs: [MatchingProgram],
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [TopicDaySection] {
        var order: [Date] = []
        var byDay: [Date: [MatchingProgram]] = [:]
        for item in programs {
            let day = calendar.startOfDay(for: item.program.startDate)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item)
        }
        return order.map { day in
            TopicDaySection(
                day: day,
                title: title(for: day, now: now, calendar: calendar, locale: locale),
                programs: byDay[day] ?? []
            )
        }
    }

    static func title(for day: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: day)
    }
}
