//
//  GuideCellTimeLabelTests.swift
//  NexusPVRTests
//
//  Program times in the macOS guide and channel cards (Midnight redesign).
//

import Foundation
import Testing
@testable import NextPVR

struct GuideCellTimeLabelTests {
    private let us = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: hour, minute: minute))!
    }

    /// ICU puts a narrow no-break space before the meridiem; compare on plain
    /// spaces.
    private func label(_ start: Date, _ end: Date, width: CGFloat = 300, locale: Locale? = nil) -> String {
        GuideCellTimeLabel.text(start: start, end: end, width: width, locale: locale ?? us, timeZone: utc)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test("Times on the hour drop their minutes")
    func onTheHour() {
        #expect(label(date(10, 0), date(11, 0)) == "10 AM – 11 AM")
        #expect(label(date(23, 0), date(0, 0)) == "11 PM – 12 AM")
    }

    @Test("Other times keep their minutes, each side on its own")
    func offTheHour() {
        #expect(label(date(10, 0), date(10, 30)) == "10 AM – 10:30 AM")
        #expect(label(date(9, 45), date(11, 0)) == "9:45 AM – 11 AM")
        #expect(label(date(12, 15), date(13, 45)) == "12:15 PM – 1:45 PM")
    }

    @Test("Narrow cells drop the meridiems")
    func narrow() {
        #expect(label(date(10, 0), date(10, 30), width: 131) == "10 – 10:30")
        #expect(label(date(10, 0), date(10, 30), width: 132) == "10 AM – 10:30 AM")
    }

    @Test("24-hour locales always keep the minutes")
    func twentyFourHour() {
        let fr = Locale(identifier: "fr_FR")
        #expect(label(date(10, 0), date(11, 0), locale: fr) == "10:00 – 11:00")
        #expect(label(date(10, 0), date(10, 30), width: 60, locale: fr) == "10:00 – 10:30")
    }

    @Test("A single time follows the same rule")
    func singleTime() {
        func time(_ d: Date) -> String {
            GuideCellTimeLabel.time(d, locale: us, timeZone: utc).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(time(date(10, 0)) == "10 AM")
        #expect(time(date(10, 45)) == "10:45 AM")
    }

    @Test("Badges need a medium-width cell")
    func badges() {
        #expect(GuideCellTimeLabel.showsBadges(width: 132))
        #expect(!GuideCellTimeLabel.showsBadges(width: 131))
    }
}
