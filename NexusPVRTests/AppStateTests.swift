//
//  AppStateTests.swift
//  NexusPVRTests
//
//  Tests for AppState: tab selection, filter management, playback state,
//  alert handling, and computed properties.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct AppStateTests {

    // MARK: - Initial State

    // Note: tests that depend on the initial `selectedTab` set
    // `testLandingTabOverride` to make the assertion deterministic
    // regardless of any state persisted in the test process's
    // UserDefaults / iCloud KV store.

    @Test("AppState initial selectedTab is guide")
    func initialSelectedTab() {
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        #expect(state.selectedTab == .guide)
    }

    @Test("AppState initial searchQuery is empty")
    func initialSearchQuery() {
        let state = AppState()
        #expect(state.searchQuery.isEmpty)
    }

    @Test("AppState initial isShowingPlayer is false")
    func initialPlayerShown() {
        let state = AppState()
        #expect(state.isShowingPlayer == false)
    }

    @Test("AppState initial recordingsFilter is completed")
    func initialRecordingsFilter() {
        let state = AppState()
        #expect(state.recordingsFilter == .completed)
    }

    // MARK: - Computed Properties

    @Test("recordingsHasActive false when count is 0")
    func recordingsHasActiveFalse() {
        let state = AppState()
        state.activeRecordingCount = 0
        #expect(state.recordingsHasActive == false)
    }

    @Test("recordingsHasActive true when count > 0")
    func recordingsHasActiveTrue() {
        let state = AppState()
        state.activeRecordingCount = 3
        #expect(state.recordingsHasActive == true)
    }

    @Test("hasSelectedRecordingsSeries false when name empty")
    func hasSelectedSeriesFalse() {
        let state = AppState()
        state.selectedRecordingsSeriesName = ""
        #expect(state.hasSelectedRecordingsSeries == false)
    }

    @Test("hasSelectedRecordingsSeries true when name set")
    func hasSelectedSeriesTrue() {
        let state = AppState()
        state.selectedRecordingsSeriesName = "Breaking Bad"
        #expect(state.hasSelectedRecordingsSeries == true)
    }

    @Test("userLevel is 10 for NextPVR")
    func userLevel() {
        let state = AppState()
        #expect(state.userLevel == 10)
    }

    // MARK: - setRecordingsFilter

    @Test("setRecordingsFilter changes filter and clears series selection")
    func setRecordingsFilter() {
        let state = AppState()
        state.selectedRecordingsSeriesName = "Series"
        state.showingRecordingsSeriesList = true

        state.setRecordingsFilter(.scheduled, userInitiated: true)

        #expect(state.recordingsFilter == .scheduled)
        #expect(state.selectedRecordingsSeriesName.isEmpty)
        #expect(state.showingRecordingsSeriesList == false)
        #expect(state.recordingsFilterUserOverride == true)
    }

    @Test("setRecordingsFilter userInitiated false does not set override")
    func setRecordingsFilterNotUserInitiated() {
        let state = AppState()
        state.setRecordingsFilter(.recording, userInitiated: false)
        #expect(state.recordingsFilter == .recording)
        #expect(state.recordingsFilterUserOverride == false)
    }

    // MARK: - selectRecordingsSeries

    @Test("selectRecordingsSeries sets name and updates state")
    func selectRecordingsSeries() {
        let state = AppState()
        state.showingRecordingsSeriesList = true

        state.selectRecordingsSeries(named: "Test Series", userInitiated: true)

        #expect(state.selectedRecordingsSeriesName == "Test Series")
        #expect(state.showingRecordingsSeriesList == false)
        #expect(state.recordingsFilterUserOverride == true)
    }

    @Test("selectRecordingsSeries userInitiated false does not set override")
    func selectRecordingsSeriesNotUserInitiated() {
        let state = AppState()
        state.selectRecordingsSeries(named: "Test", userInitiated: false)
        #expect(state.recordingsFilterUserOverride == false)
    }

    // MARK: - showRecordingsSeriesMenu

    @Test("showRecordingsSeriesMenu shows list and clears selection")
    func showRecordingsSeriesMenu() {
        let state = AppState()
        state.selectedRecordingsSeriesName = "Old"

        state.showRecordingsSeriesMenu(userInitiated: true)

        #expect(state.selectedRecordingsSeriesName.isEmpty)
        #expect(state.showingRecordingsSeriesList == true)
        #expect(state.recordingsFilterUserOverride == true)
    }

    // MARK: - playback state

    @Test("playStream sets all playback state properties")
    func playStreamSetsState() {
        let state = AppState()
        let url = URL(string: "http://example.com/stream.ts")!

        state.playStream(
            url: url,
            title: "Test Show",
            recordingId: 42,
            resumePosition: 120,
            channelId: 5,
            channelName: "ABC",
            isRecordingInProgress: true,
            recordingStartTime: Date(timeIntervalSince1970: 1000)
        )

        #expect(state.currentlyPlayingURL == url)
        #expect(state.currentlyPlayingTitle == "Test Show")
        #expect(state.currentlyPlayingRecordingId == 42)
        #expect(state.currentlyPlayingResumePosition == 120)
        #expect(state.currentlyPlayingChannelId == 5)
        #expect(state.currentlyPlayingChannelName == "ABC")
        #expect(state.currentlyPlayingIsRecordingInProgress == true)
        #expect(state.currentlyPlayingRecordingStartTime?.timeIntervalSince1970 == 1000)
        #expect(state.isShowingPlayer == true)
    }

    @Test("playStream with minimal args sets appropriate state")
    func playStreamMinimal() {
        let state = AppState()
        let url = URL(string: "http://example.com/live.ts")!

        state.playStream(url: url, title: "Live TV")

        #expect(state.currentlyPlayingURL == url)
        #expect(state.currentlyPlayingTitle == "Live TV")
        #expect(state.currentlyPlayingRecordingId == nil)
        #expect(state.isShowingPlayer == true)
    }

    @Test("playStream with channel saves watch history")
    func playStreamWithChannel() {
        let state = AppState()
        let url = URL(string: "http://example.com/live.ts")!

        state.playStream(url: url, title: "Channel 1", channelId: 1, channelName: "ABC")

        #expect(state.currentlyPlayingChannelId == 1)
        #expect(state.currentlyPlayingChannelName == "ABC")
        #expect(state.isShowingPlayer == true)
    }

    @Test("stopPlayback clears all playback state")
    func stopPlaybackClearsState() {
        let state = AppState()
        let url = URL(string: "http://example.com/stream.ts")!
        state.playStream(url: url, title: "Show", recordingId: 1)
        #expect(state.isShowingPlayer == true)

        state.stopPlayback()

        #expect(state.isShowingPlayer == false)
        #expect(state.currentlyPlayingURL == nil)
        #expect(state.currentlyPlayingTitle == nil)
        #expect(state.currentlyPlayingRecordingId == nil)
        #expect(state.currentlyPlayingResumePosition == nil)
        #expect(state.currentlyPlayingChannelId == nil)
        #expect(state.currentlyPlayingChannelName == nil)
        #expect(state.currentlyPlayingIsRecordingInProgress == false)
        #expect(state.currentlyPlayingRecordingStartTime == nil)
    }

    @Test("dismissPlayer hides player but preserves state")
    func dismissPlayerPreservesState() {
        let state = AppState()
        let url = URL(string: "http://example.com/stream.ts")!
        state.playStream(url: url, title: "Test", recordingId: 42)

        state.dismissPlayer()

        #expect(state.isShowingPlayer == false)
        #expect(state.currentlyPlayingRecordingId == 42)
        #expect(state.currentlyPlayingTitle == "Test")
    }

    // MARK: - showAlert

    @Test("showAlert sets alert state")
    func showAlertSetsState() {
        let state = AppState()
        state.showAlert("An error occurred")

        #expect(state.alertMessage == "An error occurred")
        #expect(state.isShowingAlert == true)
    }

    // MARK: - Filter selection

    @Test("setRecordingsFilter changes between all filter options")
    func setAllFilters() {
        let state = AppState()
        let filters: [RecordingsFilter] = [.completed, .recording, .scheduled]

        for filter in filters {
            state.setRecordingsFilter(filter, userInitiated: true)
            #expect(state.recordingsFilter == filter)
        }
    }

    @Test("recordingsSeriesItems initially empty")
    func recordingsSeriesItemsInitiallyEmpty() {
        let state = AppState()
        #expect(state.recordingsSeriesItems.isEmpty)
    }

    @Test("recordingsSeriesIsLoading initially false")
    func recordingsSeriesIsLoadingInitiallyFalse() {
        let state = AppState()
        #expect(state.recordingsSeriesIsLoading == false)
    }

    // MARK: - Landing tab

    // The landing tab tests use `testLandingTabOverride` so the initial
    // tab is deterministic regardless of any state that happens to be
    // persisted in the test process's UserDefaults / iCloud KV store.
    // Each test sets the override and resets it in a `defer` so leftover
    // state from a previous test can't leak in.

    @Test("applyLandingTab guide selects the guide tab")
    func applyLandingTabGuide() {
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.selectedTab = .recordings
        state.applyLandingTab(.guide)
        #expect(state.selectedTab == .guide)
    }

    @Test("applyLandingTab channels selects the channels tab")
    func applyLandingTabChannels() {
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.selectedTab = .guide
        state.applyLandingTab(.channels)
        #expect(state.selectedTab == .channels)
    }

    @Test("applyLandingTab completedRecordings selects recordings and forces completed filter")
    func applyLandingTabCompletedRecordings() {
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.selectedTab = .guide
        state.recordingsFilter = .scheduled
        state.recordingsFilterUserOverride = true
        state.selectedRecordingsSeriesName = "Series"
        state.showingRecordingsSeriesList = true

        state.applyLandingTab(.completedRecordings)

        #expect(state.selectedTab == .recordings)
        #expect(state.recordingsFilter == .completed)
        // User override is cleared because this is the app-default landing
        // behavior, not a manual filter change.
        #expect(state.recordingsFilterUserOverride == false)
        #expect(state.selectedRecordingsSeriesName.isEmpty)
        #expect(state.showingRecordingsSeriesList == false)
    }

    @Test("applyLandingTab redirects completedRecordings to Guide for userLevel < 1")
    func applyLandingTabRedirectsWhenUnavailable() {
        // Dispatcharr userLevel 0 (Streamer) does not have recordings
        // access, so asking for the Completed Recordings landing must
        // redirect to the Guide tab instead of silently landing on a
        // hidden/unavailable destination.
        #if DISPATCHERPVR
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.userLevel = 0
        state.selectedTab = .channels
        // Set a non-default filter so we can prove the redirect leaves
        // the user's manual selection alone.
        state.recordingsFilter = .scheduled
        state.recordingsFilterUserOverride = true

        state.applyLandingTab(.completedRecordings)

        #expect(state.selectedTab == .guide)
        // The recordings filter must not be touched when we redirect,
        // so the user's manual filter selection is preserved.
        #expect(state.recordingsFilter == .scheduled)
        #expect(state.recordingsFilterUserOverride == true)
        #endif
    }

    @Test("applyLandingTab keeps completedRecordings for userLevel >= 1")
    func applyLandingTabKeepsForAdmin() {
        #if DISPATCHERPVR
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.userLevel = 10
        state.selectedTab = .guide
        // Pre-set a non-default filter and series so the test verifies
        // that `applyLandingTab(.completedRecordings)` actually resets
        // those (not just that the tab ends up as `.recordings`).
        state.recordingsFilter = .scheduled
        state.recordingsFilterUserOverride = true
        state.selectedRecordingsSeriesName = "Series"
        state.showingRecordingsSeriesList = true

        state.applyLandingTab(.completedRecordings)

        #expect(state.selectedTab == .recordings)
        #expect(state.recordingsFilter == .completed)
        #expect(state.recordingsFilterUserOverride == false)
        #expect(state.selectedRecordingsSeriesName.isEmpty)
        #expect(state.showingRecordingsSeriesList == false)
        #endif
    }

    @Test("userLevel downgrade redirects hidden recordings tab to Guide")
    func userLevelDowngradeRedirectsHiddenRecordingsTab() {
        #if DISPATCHERPVR
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.userLevel = 10
        state.selectedTab = .recordings

        state.userLevel = 0

        #expect(state.selectedTab == .guide)
        #endif
    }

    @Test("userLevel downgrade leaves available tabs alone")
    func userLevelDowngradeLeavesAvailableTabsAlone() {
        #if DISPATCHERPVR
        AppState.testLandingTabOverride = .guide
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        state.userLevel = 10
        state.selectedTab = .channels

        state.userLevel = 0

        #expect(state.selectedTab == .channels)
        #endif
    }

    @Test("AppState.tab(for:) maps LandingTabOption to the correct Tab")
    func landingOptionTabMapping() {
        #expect(AppState.tab(for: .guide) == .guide)
        #expect(AppState.tab(for: .channels) == .channels)
        #expect(AppState.tab(for: .completedRecordings) == .recordings)
    }

    @Test("isLandingOptionAvailable returns true for guide and channels at any level")
    func isLandingOptionAvailableAlwaysForGuideAndChannels() {
        for level in [0, 1, 10] {
            #expect(AppState.isLandingOptionAvailable(.guide, forUserLevel: level) == true)
            #expect(AppState.isLandingOptionAvailable(.channels, forUserLevel: level) == true)
        }
    }

    @Test("isLandingOptionAvailable gates completedRecordings on userLevel >= 1")
    func isLandingOptionAvailableGatesCompletedRecordings() {
        #expect(AppState.isLandingOptionAvailable(.completedRecordings, forUserLevel: 0) == false)
        #expect(AppState.isLandingOptionAvailable(.completedRecordings, forUserLevel: 1) == true)
        #expect(AppState.isLandingOptionAvailable(.completedRecordings, forUserLevel: 10) == true)
    }

    @Test("initialLandingTab honors testLandingTabOverride")
    func initialLandingTabHonorsOverride() {
        AppState.testLandingTabOverride = .channels
        defer { AppState.testLandingTabOverride = nil }
        let state = AppState()
        #expect(state.selectedTab == .channels)
    }
}
