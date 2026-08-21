//
//  CatchupAvailabilityTests.swift
//  NexusPVRTests
//
//  Coverage for CatchupAvailability's pure gating math (#119).
//

import Testing
import Foundation
@testable import NextPVR

struct CatchupAvailabilityTests {
    private func program(startingHoursAgo hoursAgo: Double, durationMinutes: Int = 60, now: Date) -> Program {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return Program(
            id: 1,
            name: "Test Show",
            subtitle: nil,
            desc: nil,
            start: Int(start.timeIntervalSince1970),
            end: Int(end.timeIntervalSince1970),
            genres: nil,
            channelId: 42
        )
    }

    @Test("Unavailable when the channel doesn't support catch-up")
    func channelNotCatchup() {
        let now = Date()
        let p = program(startingHoursAgo: 2, now: now)
        #expect(!CatchupAvailability.isAvailable(program: p, channelIsCatchup: false, catchupDays: 7, now: now))
    }

    @Test("Unavailable when catchupDays is zero even if the channel flag is set")
    func zeroDaysWindow() {
        let now = Date()
        let p = program(startingHoursAgo: 2, now: now)
        #expect(!CatchupAvailability.isAvailable(program: p, channelIsCatchup: true, catchupDays: 0, now: now))
    }

    @Test("Unavailable for a program that hasn't ended yet")
    func programStillAiring() {
        let now = Date()
        let p = program(startingHoursAgo: 0.25, durationMinutes: 60, now: now) // started 15 min ago, airs 45 more
        #expect(!CatchupAvailability.isAvailable(program: p, channelIsCatchup: true, catchupDays: 7, now: now))
    }

    @Test("Available for an ended program within the archive window")
    func endedWithinWindow() {
        let now = Date()
        let p = program(startingHoursAgo: 5, durationMinutes: 60, now: now) // ended 4h ago
        #expect(CatchupAvailability.isAvailable(program: p, channelIsCatchup: true, catchupDays: 7, now: now))
    }

    @Test("Unavailable once the program's start falls outside catchupDays")
    func outsideWindow() {
        let now = Date()
        let p = program(startingHoursAgo: 24 * 10, durationMinutes: 60, now: now) // 10 days ago
        #expect(!CatchupAvailability.isAvailable(program: p, channelIsCatchup: true, catchupDays: 7, now: now))
    }

    @Test("Boundary just inside the archive window is available")
    func justInsideWindow() {
        let now = Date()
        let p = program(startingHoursAgo: 24 * 3 - 1, durationMinutes: 30, now: now) // ~3 days ago, within 7
        #expect(CatchupAvailability.isAvailable(program: p, channelIsCatchup: true, catchupDays: 7, now: now))
    }
}
