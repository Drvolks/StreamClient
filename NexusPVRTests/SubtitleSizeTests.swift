//
//  SubtitleSizeTests.swift
//  NexusPVRTests
//
//  Tests for SubtitleSize enum: displayName, fontSize, Codable.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct SubtitleSizeTests {

    @Test("SubtitleSize displayName returns correct labels")
    func displayNameCorrect() {
        #expect(SubtitleSize.small.displayName == "Small")
        #expect(SubtitleSize.medium.displayName == "Medium")
        #expect(SubtitleSize.large.displayName == "Large")
        #expect(SubtitleSize.extraLarge.displayName == "Extra Large")
    }

    @Test("SubtitleSize fontSize returns positive values")
    func fontSizePositive() {
        #expect(SubtitleSize.small.fontSize > 0)
        #expect(SubtitleSize.medium.fontSize > 0)
        #expect(SubtitleSize.large.fontSize > 0)
        #expect(SubtitleSize.extraLarge.fontSize > 0)
    }

    @Test("SubtitleSize fontSize increases with size")
    func fontSizeIncreases() {
        #expect(SubtitleSize.small.fontSize < SubtitleSize.medium.fontSize)
        #expect(SubtitleSize.medium.fontSize < SubtitleSize.large.fontSize)
        #expect(SubtitleSize.large.fontSize < SubtitleSize.extraLarge.fontSize)
    }

    @Test("SubtitleSize round-trips via Codable")
    func codableRoundTrip() throws {
        for size in SubtitleSize.allCases {
            let data = try JSONEncoder().encode(size)
            let decoded = try JSONDecoder().decode(SubtitleSize.self, from: data)
            #expect(decoded == size)
        }
    }

    @Test("SubtitleSize raw values are lowercase")
    func rawValuesLowercase() {
        #expect(SubtitleSize.small.rawValue == "small")
        #expect(SubtitleSize.medium.rawValue == "medium")
        #expect(SubtitleSize.large.rawValue == "large")
        #expect(SubtitleSize.extraLarge.rawValue == "extraLarge")
    }

    @Test("SubtitleSize allCases count is 4")
    func allCasesCount() {
        #expect(SubtitleSize.allCases.count == 4)
    }
}
