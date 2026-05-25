//
//  TabTests.swift
//  NexusPVRTests
//
//  Tests for Tab enum: id, icon, label, allCases, platform-specific tabs.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct TabTests {

    @Test("Tab id equals raw value")
    func idEqualsRawValue() {
        #expect(Tab.guide.id == "Guide")
        #expect(Tab.recordings.id == "Recordings")
        #expect(Tab.topics.id == "Topics")
        #expect(Tab.calendar.id == "Calendar")
        #expect(Tab.search.id == "Search")
        #expect(Tab.settings.id == "Settings")
    }

    @Test("Tab label equals raw value")
    func labelEqualsRawValue() {
        #expect(Tab.guide.label == "Guide")
        #expect(Tab.recordings.label == "Recordings")
        #expect(Tab.settings.label == "Settings")
    }

    @Test("Tab icon returns expected SF Symbol names")
    func iconReturnsExpectedSymbols() {
        #expect(Tab.guide.icon == "calendar")
        #expect(Tab.topics.icon == "star.fill")
        #expect(Tab.calendar.icon == "calendar.badge.clock")
        #expect(Tab.search.icon == "magnifyingglass")
        #expect(Tab.recordings.icon == "recordingtape")
        #expect(Tab.settings.icon == "gear")
    }

    @Test("Tab allCases user level 0 excludes recordings")
    func allCasesUserLevel0() {
        let cases = Tab.allCases(userLevel: 0)
        #expect(cases.contains(.guide))
        #expect(!cases.contains(.recordings))
        #expect(cases.contains(.topics))
        #expect(cases.contains(.search))
        #expect(cases.contains(.settings))
    }

    @Test("Tab allCases user level 1 includes recordings")
    func allCasesUserLevel1() {
        let cases = Tab.allCases(userLevel: 1)
        #expect(cases.contains(.guide))
        #expect(cases.contains(.recordings))
        #expect(cases.contains(.topics))
        #expect(cases.contains(.search))
        #expect(cases.contains(.settings))
    }

    @Test("Tab allCases user level 10 includes everything")
    func allCasesUserLevel10() {
        let cases = Tab.allCases(userLevel: 10)
        #expect(cases.contains(.guide))
        #expect(cases.contains(.recordings))
        #expect(cases.contains(.topics))
        #expect(cases.contains(.search))
        #expect(cases.contains(.settings))
    }

    #if os(iOS)
    @Test("Tab iOS tabs user level 0 excludes recordings")
    func iOSTabsUserLevel0() {
        let cases = Tab.iOSTabs(userLevel: 0)
        #expect(cases.contains(.guide))
        #expect(!cases.contains(.recordings))
        #expect(cases.contains(.topics))
        #expect(cases.contains(.calendar))
        #expect(cases.contains(.settings))
        #expect(!cases.contains(.search))
    }

    @Test("Tab iOS tabs user level 1 includes recordings")
    func iOSTabsUserLevel1() {
        let cases = Tab.iOSTabs(userLevel: 1)
        #expect(cases.contains(.recordings))
    }
    #endif

    #if os(macOS)
    @Test("Tab macOS tabs user level 0 excludes recordings")
    func macOSTabsUserLevel0() {
        let cases = Tab.macOSTabs(userLevel: 0)
        #expect(cases.contains(.guide))
        #expect(!cases.contains(.recordings))
        #expect(cases.contains(.topics))
        #expect(cases.contains(.calendar))
        #expect(cases.contains(.settings))
        #expect(!cases.contains(.search))
    }

    @Test("Tab macOS tabs user level 1 includes recordings")
    func macOSTabsUserLevel1() {
        let cases = Tab.macOSTabs(userLevel: 1)
        #expect(cases.contains(.recordings))
    }
    #endif

    #if os(tvOS)
    @Test("Tab tvOS tabs user level 0 excludes recordings and search")
    func tvOSTabsUserLevel0() {
        let cases = Tab.tvOSTabs(userLevel: 0)
        #expect(cases.contains(.guide))
        #expect(!cases.contains(.recordings))
        #expect(cases.contains(.topics))
        #expect(cases.contains(.settings))
        #expect(!cases.contains(.search))
    }

    @Test("Tab tvOS tabs user level 1 includes recordings")
    func tvOSTabsUserLevel1() {
        let cases = Tab.tvOSTabs(userLevel: 1)
        #expect(cases.contains(.recordings))
    }
    #endif
}
