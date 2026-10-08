//
//  TVRootExitActionTests.swift
//  NexusPVRTests
//
//  Tests for the tvOS root Back-button decision (#155).
//

import Testing
@testable import NextPVR

struct TVRootExitActionTests {

    private func resolve(
        tab: Tab = .guide,
        sidebarHasFocus: Bool = false,
        popup: Bool = false,
        eventLog: Bool = false,
        category: Bool = false,
        blocks: Bool = false
    ) -> TVRootExitAction {
        TVRootExitAction.resolve(
            selectedTab: tab,
            sidebarHasFocus: sidebarHasFocus,
            settingsHasPopup: popup,
            settingsShowingEventLog: eventLog,
            settingsShowingCategory: category,
            blocksSidebarExit: blocks
        )
    }

    @Test("Back with sidebar focused hands the press to the system")
    func sidebarFocusedExitsApp() {
        for tab in [Tab.guide, .channels, .recordings, .topics, .search, .settings] {
            #expect(resolve(tab: tab, sidebarHasFocus: true) == .exitToSystem)
        }
    }

    @Test("Back from content moves focus to the sidebar")
    func contentFocusedGoesToSidebar() {
        for tab in [Tab.guide, .channels, .recordings, .topics, .search, .settings] {
            #expect(resolve(tab: tab, sidebarHasFocus: false) == .focusSidebar)
        }
    }

    @Test("Settings popup is dismissed before anything else")
    func settingsPopupWins() {
        #expect(resolve(tab: .settings, sidebarHasFocus: true, popup: true, eventLog: true) == .dismissSettingsPopup)
        #expect(resolve(tab: .settings, popup: true, blocks: true) == .dismissSettingsPopup)
    }

    @Test("Settings event log is dismissed before leaving the app")
    func settingsEventLogDismissed() {
        #expect(resolve(tab: .settings, sidebarHasFocus: true, eventLog: true) == .dismissEventLog)
        #expect(resolve(tab: .settings, eventLog: true, blocks: true) == .dismissEventLog)
    }

    @Test("Back from a Settings category page returns to the index")
    func settingsCategoryClosesToIndex() {
        #expect(resolve(tab: .settings, category: true) == .closeSettingsCategory)
        #expect(resolve(tab: .settings, category: true, blocks: true) == .closeSettingsCategory)
    }

    @Test("Overlays close before the Settings category page")
    func settingsOverlaysBeforeCategory() {
        #expect(resolve(tab: .settings, popup: true, category: true) == .dismissSettingsPopup)
        #expect(resolve(tab: .settings, eventLog: true, category: true) == .dismissEventLog)
    }

    @Test("Back from the sidebar leaves the app even with a category page open")
    func settingsCategoryFromSidebarExits() {
        #expect(resolve(tab: .settings, sidebarHasFocus: true, category: true) == .exitToSystem)
    }

    @Test("Other tabs ignore the Settings category flag")
    func categoryFlagOnlyInSettings() {
        #expect(resolve(tab: .guide, category: true) == .focusSidebar)
    }

    @Test("Settings ignores the sidebar block flag once overlays are closed")
    func settingsIgnoresBlockFlag() {
        #expect(resolve(tab: .settings, blocks: true) == .focusSidebar)
        #expect(resolve(tab: .settings, sidebarHasFocus: true, blocks: true) == .exitToSystem)
    }

    @Test("Other tabs consume the press while a child view blocks it")
    func blockFlagIgnoresPress() {
        #expect(resolve(tab: .guide, blocks: true) == .ignore)
        #expect(resolve(tab: .guide, sidebarHasFocus: true, blocks: true) == .ignore)
    }
}
