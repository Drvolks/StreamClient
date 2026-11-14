//
//  TVDetailCoverGateTests.swift
//  NexusPVRTests
//
//  The tvOS player waits for detail pages to go before presenting.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct TVDetailCoverGateTests {
    @Test("The gate is open until a detail page appears, and again once it has gone")
    func opensAndCloses() {
        let gate = TVDetailCoverGate()
        let page = UUID()
        #expect(!gate.hasOpenCover)
        gate.coverAppeared(page)
        #expect(gate.hasOpenCover)
        gate.coverDisappeared(page)
        #expect(!gate.hasOpenCover)
    }

    @Test("Repeated appear calls for one page don't keep the gate shut")
    func repeatedAppearIsIdempotent() {
        let gate = TVDetailCoverGate()
        let page = UUID()
        gate.coverAppeared(page)
        gate.coverAppeared(page)
        gate.coverDisappeared(page)
        #expect(!gate.hasOpenCover)
    }

    @Test("Stacked pages keep the gate shut until the last one goes")
    func stackedPages() {
        let gate = TVDetailCoverGate()
        let first = UUID(), second = UUID()
        gate.coverAppeared(first)
        gate.coverAppeared(second)
        gate.coverDisappeared(first)
        #expect(gate.hasOpenCover)
        gate.coverDisappeared(second)
        #expect(!gate.hasOpenCover)
        gate.coverDisappeared(second)
        #expect(!gate.hasOpenCover)
    }
}
