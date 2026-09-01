//
//  VideoAspectCorrectionTests.swift
//  NexusPVRTests
//
//  Tests for the PixelBuffer renderer's anamorphic aspect handling (issue #152).
//

import Testing
import CoreGraphics
@testable import NextPVR

struct VideoAspectCorrectionTests {

    @Test("Anamorphic SD (720x576, 64:45 SAR) gets a 16:9 rect, not the coded 5:4")
    func anamorphicSDFillsWidescreenRect() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rect = VideoAspectCorrection.fittedRect(displayAspect: 16.0 / 9.0, in: bounds)
        #expect(rect == bounds)
    }

    @Test("A rect wider than the view is letterboxed and centered")
    func letterboxesWideVideo() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let rect = VideoAspectCorrection.fittedRect(displayAspect: 2.0, in: bounds)
        #expect(rect == CGRect(x: 0, y: 250, width: 1000, height: 500))
    }

    @Test("A rect taller than the view is pillarboxed and centered")
    func pillarboxesNarrowVideo() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let rect = VideoAspectCorrection.fittedRect(displayAspect: 0.5, in: bounds)
        #expect(rect == CGRect(x: 250, y: 0, width: 500, height: 1000))
    }

    @Test("Centering respects a non-zero origin")
    func centersWithinOffsetBounds() {
        let bounds = CGRect(x: 100, y: 50, width: 400, height: 400)
        let rect = VideoAspectCorrection.fittedRect(displayAspect: 2.0, in: bounds)
        #expect(rect == CGRect(x: 100, y: 150, width: 400, height: 200))
    }

    @Test("Unusable aspects or bounds fall back to the full bounds")
    func fallsBackWhenAspectUnknown() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(VideoAspectCorrection.fittedRect(displayAspect: 0, in: bounds) == bounds)
        #expect(VideoAspectCorrection.fittedRect(displayAspect: -1.5, in: bounds) == bounds)
        #expect(VideoAspectCorrection.fittedRect(displayAspect: .nan, in: bounds) == bounds)
        #expect(VideoAspectCorrection.fittedRect(displayAspect: .infinity, in: bounds) == bounds)
        let empty = CGRect.zero
        #expect(VideoAspectCorrection.fittedRect(displayAspect: 1.777, in: empty) == empty)
    }
}
