//
//  GuideCellTimeLabelTests.swift
//  NexusPVRTests
//
//  The width-adaptive time range in macOS guide cells (Midnight redesign).
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
    private func label(width: CGFloat, locale: Locale? = nil) -> String {
        GuideCellTimeLabel.text(start: date(7, 30), end: date(9, 0), width: width, locale: locale ?? us, timeZone: utc)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test("Wide cells show both meridiems")
    func wide() {
        #expect(label(width: 200) == "7:30 AM – 9:00 AM")
        #expect(label(width: 480) == "7:30 AM – 9:00 AM")
    }

    @Test("Medium cells keep only the end meridiem")
    func medium() {
        #expect(label(width: 132) == "7:30 – 9:00 AM")
        #expect(label(width: 199) == "7:30 – 9:00 AM")
    }

    @Test("Narrow cells drop the meridiems")
    func narrow() {
        #expect(label(width: 131) == "7:30 – 9:00")
        #expect(label(width: 60) == "7:30 – 9:00")
    }

    @Test("24-hour locales read the same at every width")
    func twentyFourHour() {
        let fr = Locale(identifier: "fr_FR")
        #expect(label(width: 300, locale: fr) == "07:30 – 09:00")
        #expect(label(width: 60, locale: fr) == "07:30 – 09:00")
    }

    @Test("Badges need a medium-width cell")
    func badges() {
        #expect(GuideCellTimeLabel.showsBadges(width: 132))
        #expect(!GuideCellTimeLabel.showsBadges(width: 131))
    }
}
