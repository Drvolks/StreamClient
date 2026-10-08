//
//  SettingsCategoryTests.swift
//  NexusPVRTests
//
//  The macOS Settings index (Midnight redesign).
//

import Testing
@testable import NextPVR

struct SettingsCategoryTests {

    @Test("Category order matches the design")
    func order() {
        #expect(SettingsCategory.allCases.map(\.title) == [
            "Server", "General", "Playback", "Subtitles", "Guide", "Topics", "Recordings", "Advanced"
        ])
    }

    @Test("Raw values are stable, since the selection is saved by raw value")
    func rawValuesAreStable() {
        #expect(SettingsCategory.server.rawValue == 0)
        #expect(SettingsCategory.advanced.rawValue == 7)
        #expect(SettingsCategory(rawValue: 2) == .playback)
    }

    @Test("Every category has a hint")
    func hints() {
        for category in SettingsCategory.allCases {
            #expect(!category.hint.isEmpty)
        }
    }
}
