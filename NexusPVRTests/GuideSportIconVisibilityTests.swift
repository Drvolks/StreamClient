//
//  GuideSportIconVisibilityTests.swift
//  NexusPVRTests
//
//  Coverage for the Guide's sport icon duration and width gates (#137).
//

import Foundation
import Testing
@testable import NextPVR

struct GuideSportIconVisibilityTests {
    private func program(duration: TimeInterval) -> Program {
        Program(
            id: 1,
            name: "Hockey",
            subtitle: nil,
            desc: nil,
            start: 0,
            end: Int(duration),
            genres: ["Sports", "Hockey"],
            channelId: 1
        )
    }

    @Test("Sport icon is hidden for a 30-minute program")
    func hiddenAtThirtyMinuteBoundary() {
        #expect(
            !GuideSportIconVisibility.shouldShow(
                for: program(duration: 30 * 60),
                cellWidth: 300,
                minimumCellWidth: 100
            )
        )
    }

    @Test("Sport icon may be shown for a program longer than 30 minutes")
    func shownAboveThirtyMinutesWhenWideEnough() {
        #expect(
            GuideSportIconVisibility.shouldShow(
                for: program(duration: 31 * 60),
                cellWidth: 300,
                minimumCellWidth: 200
            )
        )
    }

    @Test("Sport icon remains hidden below the platform width threshold")
    func hiddenWhenCellIsTooNarrow() {
        #expect(
            !GuideSportIconVisibility.shouldShow(
                for: program(duration: 60 * 60),
                cellWidth: 200,
                minimumCellWidth: 200
            )
        )
    }
}
