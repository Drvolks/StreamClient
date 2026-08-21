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

    // MARK: - Sidebar / layout scales

    @Test("Sidebar scale increases with size")
    func sidebarScaleIncreases() {
        #expect(UIFontSize.small.sidebarScale < UIFontSize.medium.sidebarScale)
        #expect(UIFontSize.medium.sidebarScale < UIFontSize.large.sidebarScale)
        #expect(UIFontSize.large.sidebarScale < UIFontSize.xLarge.sidebarScale)
    }

    /// The sidebar deliberately reacts harder to the setting than the rest
    /// of the app: its baseline point sizes are small, so the shared curve
    /// made changing the setting look like it had barely moved the menu.
    @Test("Sidebar scale spreads wider than the font scale")
    func sidebarScaleSpreadsWiderThanFontScale() {
        #expect(UIFontSize.small.sidebarScale < UIFontSize.small.scale)
        #expect(UIFontSize.large.sidebarScale > UIFontSize.large.scale)
        #expect(UIFontSize.xLarge.sidebarScale > UIFontSize.xLarge.scale)
    }

    @Test("Sidebar scale stays within a sane range")
    func sidebarScaleBounded() {
        for size in UIFontSize.allCases {
            #expect(size.sidebarScale > 0)
            #expect(size.sidebarScale <= 1.6, "sidebar scale \(size.sidebarScale) for \(size) is unreasonably large")
        }
    }

    @Test("Layout scale matches the font scale")
    func layoutScaleMatchesFontScale() {
        // Row heights and icons grow with the text they hold; if these ever
        // diverge, text starts clipping at the larger steps.
        for size in UIFontSize.allCases {
            #expect(size.layoutScale == size.scale)
        }
    }

    @Test("Medium is the baseline for every scale")
    func mediumIsBaselineEverywhere() {
        // Upgrade safety: the default must leave fonts, sidebar and layout
        // metrics byte-for-byte identical to the pre-#107 build.
        #expect(UIFontSize.medium.scale == 1.0)
        #expect(UIFontSize.medium.sidebarScale == 1.0)
        #expect(UIFontSize.medium.layoutScale == 1.0)
    }
}
