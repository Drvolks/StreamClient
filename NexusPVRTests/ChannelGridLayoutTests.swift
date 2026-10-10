//
//  ChannelGridLayoutTests.swift
//  NexusPVRTests
//
//  Tests for the tvOS "Channels per Row" setting (#177).
//

import Testing
import Foundation
@testable import NextPVR

struct ChannelGridLayoutTests {

    @Test("Only the offered column counts are usable; anything else is Auto")
    func columnsValidation() {
        #expect(ChannelGridLayout.columns(nil) == nil)
        for option in ChannelGridLayout.columnOptions {
            #expect(ChannelGridLayout.columns(option) == option)
        }
        #expect(ChannelGridLayout.columns(0) == nil)
        #expect(ChannelGridLayout.columns(7) == nil)
        #expect(ChannelGridLayout.columns(-3) == nil)
    }

    @Test("Labels read Auto or the count")
    func labels() {
        #expect(ChannelGridLayout.label(nil) == "Auto")
        #expect(ChannelGridLayout.label(4) == "4")
    }

    @Test("Auto and an unmeasured grid draw cards at scale 1")
    func scaleDefaults() {
        #expect(ChannelGridLayout.cardScale(columns: nil, gridWidth: 1500, spacing: 16) == 1)
        #expect(ChannelGridLayout.cardScale(columns: 4, gridWidth: 0, spacing: 16) == 1)
    }

    @Test("A card at the reference width draws at scale 1")
    func scaleAtReferenceWidth() {
        let width = ChannelGridLayout.referenceCardWidth * 4 + 16 * 3
        #expect(ChannelGridLayout.cardScale(columns: 4, gridWidth: width, spacing: 16) == 1)
    }

    @Test("Fewer columns give larger cards, within the scale range")
    func scaleFollowsColumns() {
        let scales = ChannelGridLayout.columnOptions.map {
            ChannelGridLayout.cardScale(columns: $0, gridWidth: 1500, spacing: 16)
        }
        #expect(scales == scales.sorted(by: >))
        #expect(scales.allSatisfy { ChannelGridLayout.scaleRange.contains($0) })
        #expect(scales.first == ChannelGridLayout.scaleRange.upperBound)
        #expect(scales.last == ChannelGridLayout.scaleRange.lowerBound)
    }

    @Test("channelsPerRow round-trips and defaults to Auto")
    func preferenceRoundTrip() throws {
        var prefs = UserPreferences()
        #expect(prefs.channelsPerRow == nil)
        prefs.channelsPerRow = 6
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded.channelsPerRow == 6)

        let legacy = try JSONDecoder().decode(UserPreferences.self, from: Data("{}".utf8))
        #expect(legacy.channelsPerRow == nil)
    }
}
