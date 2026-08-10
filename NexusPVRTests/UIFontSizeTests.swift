//
//  UIFontSizeTests.swift
//  NexusPVRTests
//
//  Tests for UIFontSize enum: displayName, scale, Codable (issue #107).
//  Mirrors SubtitleSizeTests.swift pattern.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct UIFontSizeTests {

    @Test("UIFontSize displayName returns correct labels")
    func displayNameCorrect() {
        #expect(UIFontSize.small.displayName == "Small")
        #expect(UIFontSize.medium.displayName == "Medium")
        #expect(UIFontSize.large.displayName == "Large")
        #expect(UIFontSize.xLarge.displayName == "X-Large")
    }

    @Test("UIFontSize scale is positive and bounded")
    func scalePositiveAndBounded() {
        for size in UIFontSize.allCases {
            #expect(size.scale > 0)
            #expect(size.scale <= 1.5, "scale \(size.scale) for \(size) is unreasonably large")
        }
    }

    @Test("UIFontSize scale increases with size")
    func scaleIncreases() {
        #expect(UIFontSize.small.scale < UIFontSize.medium.scale)
        #expect(UIFontSize.medium.scale < UIFontSize.large.scale)
        #expect(UIFontSize.large.scale < UIFontSize.xLarge.scale)
    }

    @Test("UIFontSize medium is the de facto baseline (scale == 1.0)")
    func mediumIsBaseline() {
        // Critical for upgrade safety: defaulting to medium must
        // produce zero visual change for existing users.
        #expect(UIFontSize.medium.scale == 1.0)
    }

    @Test("UIFontSize round-trips via Codable")
    func codableRoundTrip() throws {
        for size in UIFontSize.allCases {
            let data = try JSONEncoder().encode(size)
            let decoded = try JSONDecoder().decode(UIFontSize.self, from: data)
            #expect(decoded == size)
        }
    }

    @Test("UIFontSize raw values match JSON shape")
    func rawValuesMatchJsonShape() {
        // These are the on-the-wire values that get persisted to
        // iCloud and UserDefaults. Changing them is a breaking change
        // for any user with a prior value. Pin the shape explicitly
        // so a future rename doesn't silently corrupt prefs.
        #expect(UIFontSize.small.rawValue == "small")
        #expect(UIFontSize.medium.rawValue == "medium")
        #expect(UIFontSize.large.rawValue == "large")
        #expect(UIFontSize.xLarge.rawValue == "xLarge")
    }

    @Test("UIFontSize allCases count is 4")
    func allCasesCount() {
        #expect(UIFontSize.allCases.count == 4)
    }

    @Test("UIFontSize decodes from a missing key as medium (backward-compatible)")
    func backwardCompatibleDecode() throws {
        // Simulates a prefs blob written before #107 shipped. The
        // synthesized enum decoder does not see a `uiFontSize` key
        // and falls back to .medium via the `decodeIfPresent ?? .medium`
        // in UserPreferences.init(from:).
        let legacy = #"{"keywords": []}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(legacy.utf8))
        #expect(prefs.uiFontSize == .medium)
    }
}
