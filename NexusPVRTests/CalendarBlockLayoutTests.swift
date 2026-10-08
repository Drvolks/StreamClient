//
//  CalendarBlockLayoutTests.swift
//  NexusPVRTests
//

import Foundation
import Testing
@testable import NextPVR

struct CalendarBlockLayoutTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ id: String, from startMinutes: Double, to endMinutes: Double) -> CalendarBlockLayout.Item {
        .init(id: id, start: base.addingTimeInterval(startMinutes * 60), end: base.addingTimeInterval(endMinutes * 60))
    }

    @Test("A short program right before another stops short of it instead of overlapping")
    func shortProgramDoesNotOverlapNext() {
        // 15 minutes at 60pt/hour is 15pt, under the 20pt minimum.
        let slots = CalendarBlockLayout.layout(
            [item("short", from: 0, to: 15), item("next", from: 15, to: 75)],
            hourHeight: 60, minHeight: 20
        )
        #expect(slots["short"] == .init(column: 0, totalColumns: 1, height: 14))
        #expect(slots["next"] == .init(column: 0, totalColumns: 1, height: 60))
    }

    @Test("A short program with room after it gets the minimum height")
    func shortProgramKeepsMinimum() {
        let slots = CalendarBlockLayout.layout(
            [item("short", from: 0, to: 10), item("later", from: 60, to: 120)],
            hourHeight: 60, minHeight: 20
        )
        #expect(slots["short"]?.height == 20)
    }

    @Test("Overlapping programs share the width in columns")
    func overlapsGetColumns() {
        let slots = CalendarBlockLayout.layout(
            [item("a", from: 0, to: 60), item("b", from: 30, to: 90), item("c", from: 120, to: 150)],
            hourHeight: 60, minHeight: 20
        )
        #expect(slots["a"]?.column == 0)
        #expect(slots["b"]?.column == 1)
        #expect(slots["a"]?.totalColumns == 2)
        #expect(slots["b"]?.totalColumns == 2)
        #expect(slots["c"] == .init(column: 0, totalColumns: 1, height: 30))
    }

    @Test("Only the next block in the same column limits the height")
    func otherColumnsDoNotClamp() {
        // "b" starts right after "a" ends, but in another column because of "long".
        let slots = CalendarBlockLayout.layout(
            [item("long", from: 0, to: 120), item("a", from: 0, to: 10), item("b", from: 10, to: 60)],
            hourHeight: 60, minHeight: 20
        )
        #expect(slots["a"]?.column != slots["long"]?.column)
        #expect(slots["a"]?.height == 9) // clamped by "b", in its own column
    }
}
