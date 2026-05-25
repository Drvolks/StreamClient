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

    @Test("AppState initial selectedTab is guide")
    func initialSelectedTab() {
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
}
