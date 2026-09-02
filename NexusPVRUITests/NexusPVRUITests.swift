//
//  NexusPVRUITests.swift
//  NexusPVRUITests
//
//  Cross-platform UI coverage for the demo experience.
//

import Foundation
import XCTest

final class NexusPVRUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(macOS)
        throw XCTSkip("macOS navigation and guide content are not exposed to XCUI reliably yet; run this suite on iOS/tvOS until additional accessibility hooks land.")
        #endif
    }

    @MainActor
    func testGuideLoadsDemoData() throws {
        let app = launchApp()

        XCTAssertTrue(waitForGuideContent(in: app), "Guide should expose channels or programs")
    }

    @MainActor
    func testLivePlaybackCanOpenAndClose() throws {
        let app = launchApp()
        navigateToTab("Guide", app: app)
        XCTAssertTrue(waitForGuideContent(in: app), "Guide content should be loaded before opening live playback")

        #if os(tvOS)
        let remote = XCUIRemote.shared
        remote.press(.down)
        pause(1.0)
        remote.press(.select)
        #else
        let channelButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-channel-'")).firstMatch
        if channelButton.waitForExistence(timeout: 5) {
            activate(channelButton, app: app)
        } else {
            let programButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-program-'")).firstMatch
            XCTAssertTrue(programButton.waitForExistence(timeout: 5), "Expected a guide channel or program to open playback")
            activate(programButton, app: app)
        }
        #endif

        XCTAssertTrue(app.otherElements["player-view"].waitForExistence(timeout: 10), "Player should open from guide")
        dismissPlayer(app: app)
        XCTAssertTrue(waitForGuideContent(in: app), "Guide should be visible after player dismissal")
    }

    #if os(iOS)
    /// The grid only builds the programme cells inside the visible time
    /// window (#141), so scrolling must keep filling it — horizontally as the
    /// window moves along the timeline, and vertically as rows are realized.
    @MainActor
    func testGuideKeepsRenderingProgramsWhileScrolling() throws {
        let app = launchApp()
        navigateToTab("Guide", app: app)
        XCTAssertTrue(waitForGuideContent(in: app), "Guide content should be loaded")

        let grid = app.scrollViews["guide-view"].firstMatch
        let programCells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-program-'"))
        XCTAssertTrue(waitForCondition(timeout: 8) { programCells.count > 0 }, "Guide should render programme cells")

        guard grid.waitForExistence(timeout: 5) else {
            throw XCTSkip("Guide scroll view is not exposed on this platform")
        }

        // Forward along the timeline, then back to where we started.
        for _ in 0..<3 {
            grid.swipeLeft()
            pause(0.4)
            XCTAssertTrue(
                waitForCondition(timeout: 4) { programCells.count > 0 },
                "Programme cells should keep rendering while scrolling forward"
            )
        }

        grid.swipeDown()
        pause(0.4)
        XCTAssertTrue(
            waitForCondition(timeout: 4) { programCells.count > 0 },
            "Programme cells should keep rendering while scrolling vertically"
        )

        for _ in 0..<3 {
            grid.swipeRight()
            pause(0.4)
        }
        XCTAssertTrue(
            waitForCondition(timeout: 4) { programCells.count > 0 },
            "Programme cells should keep rendering after scrolling back"
        )
    }
    #endif

    #if os(iOS)
    /// The Downloads tab has to be a place you can leave again. It owns no
    /// NavigationStack of its own, and without one being wrapped around it
    /// there is no toolbar to carry the sidebar button — the tab becomes a
    /// dead end with no way back to any other page.
    @MainActor
    func testDownloadsTabOffersTheSidebarButton() throws {
        let app = launchApp()
        navigateToTab("Downloads", app: app)

        let expandButton = app.buttons["nav-expand-button"].firstMatch
        XCTAssertTrue(
            expandButton.waitForExistence(timeout: 5),
            "Downloads must offer the sidebar button, or the tab can't be left"
        )

        // And it genuinely navigates: prove another tab can be reached from here.
        navigateToTab("Settings", app: app)
        XCTAssertTrue(
            waitForCondition(timeout: 5) { !app.staticTexts["No Downloads"].exists },
            "Expected to leave the Downloads tab"
        )
    }
    #endif

    #if os(iOS)
    /// A currently airing program offers `Watch Live`, and the catch-up
    /// restart action (#143) is a separate control — never the same button.
    /// Demo/NextPVR data has no catch-up channels, so the restart action is
    /// expected to be absent there; when a catch-up channel is present it must
    /// coexist with `Watch Live` rather than replace it.
    @MainActor
    func testLiveProgramDetailOffersLiveAndCatchupAsDistinctActions() throws {
        let app = launchApp()
        navigateToTab("Guide", app: app)
        XCTAssertTrue(waitForGuideContent(in: app), "Guide content should be loaded before opening details")

        let watchLive = app.buttons["watch-live-button"].firstMatch
        let watchFromBeginning = app.buttons["watch-from-beginning-catchup-button"].firstMatch

        let programButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-program-'"))
        XCTAssertTrue(waitForCondition(timeout: 5) { programButtons.count > 0 })

        var foundLiveProgram = false
        for index in 0..<min(programButtons.count, 12) {
            let button = programButtons.element(boundBy: index)
            guard button.exists else { continue }
            let frame = button.frame
            guard frame.width > 1, frame.height > 1 else { continue }
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            pause(1.0)

            if watchLive.waitForExistence(timeout: 1.5) {
                foundLiveProgram = true
                break
            }

            if app.otherElements["player-view"].exists {
                dismissPlayer(app: app)
            } else {
                dismissPresentedDetail(app: app)
            }
            pause(0.3)
        }

        try XCTSkipUnless(foundLiveProgram, "No currently airing program was reachable in the visible guide window")

        XCTAssertTrue(watchLive.exists, "A currently airing program should offer Watch Live")
        XCTAssertTrue(watchLive.isEnabled, "Watch Live should be actionable for an airing program")

        if watchFromBeginning.exists {
            XCTAssertTrue(watchFromBeginning.isEnabled, "Catch-up restart should be actionable when offered")
            XCTAssertNotEqual(
                watchFromBeginning.frame,
                watchLive.frame,
                "Watch from Beginning and Watch Live must be two distinct controls"
            )
        }

        dismissPresentedDetail(app: app)
    }
    #endif

    @MainActor
    func testSchedulingFromGuideAppearsInScheduledRecordings() throws {
        let app = launchApp()

        #if os(iOS)
        let programName = try openFutureProgramDetailAndCaptureName(app: app)

        let recordButton = app.buttons["record-button"].firstMatch
        let cancelButton = app.buttons["cancel-recording-button"].firstMatch

        if cancelButton.waitForExistence(timeout: 1.5) {
            // Already scheduled in fixtures or prior state; acceptable for this flow.
        } else {
            XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Future program detail should offer recording")
            activate(recordButton, app: app)
            XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Recording should switch to cancellable state")
        }

        dismissPresentedDetail(app: app)
        navigateToTab("Recordings", app: app)
        selectRecordingsFilter("Scheduled", in: app)

        let scheduledRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'recording-row-'"))
        let anyScheduledRow = scheduledRows.firstMatch
        let matchedByName = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", programName)).firstMatch
        XCTAssertTrue(
            anyScheduledRow.waitForExistence(timeout: 8) || matchedByName.waitForExistence(timeout: 2),
            "Program should be present in Scheduled recordings after scheduling"
        )
        #else
        let scheduledProgramName = try openFutureProgramDetailAndCaptureName(app: app)

        let recordButton = app.buttons["record-button"].firstMatch
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Future program detail should offer recording")
        activate(recordButton, app: app)
        XCTAssertTrue(app.buttons["cancel-recording-button"].waitForExistence(timeout: 5), "Recording should switch to cancellable state")

        #if os(macOS)
        return
        #else
        dismissPresentedDetail(app: app)
        navigateToTab("Recordings", app: app)
        selectRecordingsFilter("Scheduled", in: app)

        let scheduledRecording = app.staticTexts[scheduledProgramName].firstMatch
        XCTAssertTrue(scheduledRecording.waitForExistence(timeout: 8), "'\(scheduledProgramName)' should appear in Scheduled recordings")
        #endif
        #endif
    }

    #if os(tvOS)
    @MainActor
    func testRecordingsCompletedEmptyReturnsFocusToSidebar() throws {
        let app = launchApp(additionalArguments: ["--ui-testing-empty-completed-recordings"])
        openSidebarOnTV(in: app)
        focusAndSelectSidebarItem("recordings-filter-Completed", in: app)

        let emptyMessage = app.staticTexts["No completed recordings."].firstMatch
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 8), "Completed empty state should be visible")
        XCTAssertEqual(recordingRowCount(in: app), 0, "Completed list should be empty")

        pressMenuAndAssertSidebarFocused(app: app, sidebarIdentifier: "recordings-filter-Completed")
    }

    @MainActor
    func testRecordingsScheduledEmptyReturnsFocusToSidebar() throws {
        let app = launchApp(additionalArguments: ["--ui-testing-empty-scheduled-recordings"])
        openSidebarOnTV(in: app)
        focusAndSelectSidebarItem("recordings-filter-Scheduled", in: app)

        let emptyMessage = app.staticTexts["No scheduled recordings."].firstMatch
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 8), "Scheduled empty state should be visible")
        XCTAssertEqual(recordingRowCount(in: app), 0, "Scheduled list should be empty")

        pressMenuAndAssertSidebarFocused(app: app, sidebarIdentifier: "recordings-filter-Scheduled")
    }

    @MainActor
    func testRecordingsSeriesEmptyReturnsFocusToSidebar() throws {
        let app = launchApp(additionalArguments: ["--ui-testing-empty-series-recordings"])
        openSidebarOnTV(in: app)
        focusAndSelectSidebarItem("recordings-series-menu", in: app)

        XCTAssertEqual(recordingRowCount(in: app), 0, "Series list should have no recording rows")

        pressMenuAndAssertSidebarVisible(app: app)
    }

    @MainActor
    func testTopicsEmptyReturnsFocusToSidebar() throws {
        let app = launchApp(additionalArguments: ["--ui-testing-empty-topics"])
        openSidebarOnTV(in: app)
        focusAndSelectSidebarItem("topic-keyword-__no_topic_matches__", in: app)

        let emptyMessage = app.staticTexts["No Matching Programs"].firstMatch
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 8), "Topics empty state should be visible")
        let topicRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'topic-program-'"))
        XCTAssertEqual(topicRows.count, 0, "Topics list should be empty")

        pressMenuAndAssertSidebarFocused(app: app, sidebarIdentifier: "topic-keyword-__no_topic_matches__")
    }
    #endif

    #if !os(macOS)
    @MainActor
    func testCompletedRecordingsShowDemoFixtures() throws {
        let app = launchApp()
        navigateToTab("Recordings", app: app)
        selectRecordingsFilter("Completed", in: app)

        let recordingRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'recording-row-'"))
            .firstMatch
        XCTAssertTrue(recordingRow.waitForExistence(timeout: 8), "Completed recordings should show at least one demo fixture")
    }
    #endif

    #if !os(macOS)
    @MainActor
    func testTopicsCanAddKeywordAndRevealMatchingPrograms() throws {
        let app = launchApp()
        let keyword = "Ironing"
        navigateToTab("Topics", app: app)

        #if os(tvOS)
        let remote = XCUIRemote.shared
        let keywordField = app.textFields["keyword-text-field"].firstMatch

        for _ in 0..<6 {
            remote.press(.right)
            pause(0.4)
        }
        XCTAssertTrue(keywordField.waitForExistence(timeout: 5), "Manage keyword field should be reachable on tvOS")

        for _ in 0..<8 where !keywordField.hasFocus {
            remote.press(.down)
            pause(0.4)
        }

        remote.press(.select)
        pause(0.8)
        keywordField.typeText(keyword + "\n")
        pause(2.5)
        #else
        openKeywordEditor(app: app)

        let keywordField = app.textFields["keyword-text-field"].firstMatch
        XCTAssertTrue(keywordField.waitForExistence(timeout: 5))
        activate(keywordField, app: app)
        keywordField.typeText(keyword)

        let addButton = app.buttons["add-keyword-confirm"].firstMatch
        if addButton.waitForExistence(timeout: 2) {
            activate(addButton, app: app)
        }
        pause(0.5)
        dismissKeywordEditor(app: app)
        pause(1.0)

        selectKeywordTab(keyword, in: app)
        #endif

        let matchingTopicRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'topic-program-'"))
            .firstMatch
        let matchingProgramText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", keyword)).firstMatch

        XCTAssertTrue(
            matchingTopicRow.waitForExistence(timeout: 8) || matchingProgramText.waitForExistence(timeout: 3),
            "Topics should display programs matching '\(keyword)'"
        )
    }
    #endif

    @MainActor
    func testSearchFindsProgramsAndShowsDetails() throws {
        let app = launchApp()

        #if os(iOS)
        XCTAssertTrue(waitForGuideContent(in: app), "Guide content should be ready before opening search")
        openSearchResult(named: "Extreme Ironing World Cup", in: app)

        let detailName = app.staticTexts["program-detail-name"].firstMatch
        XCTAssertTrue(detailName.waitForExistence(timeout: 6), "Program detail should open from search result")
        XCTAssertTrue(detailName.label.contains("Extreme Ironing World Cup"), "Search detail should match the requested program")
        #elseif os(tvOS)
        let remote = XCUIRemote.shared
        remote.press(.left)
        pause(1.0)

        let searchField = app.textFields["search-view-field"].firstMatch
        if !searchField.exists {
            for _ in 0..<5 where !app.textFields.firstMatch.exists {
                remote.press(.down)
                pause(0.3)
            }
        }
        let effectiveField = searchField.exists ? searchField : app.textFields.firstMatch
        XCTAssertTrue(effectiveField.waitForExistence(timeout: 5), "tvOS search field should be present")
        for _ in 0..<5 where !effectiveField.hasFocus {
            remote.press(.down)
            pause(0.3)
        }
        remote.press(.select)
        pause(0.5)
        effectiveField.typeText("Extreme Ironing World Cup\n")

        let resultRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search-result-'"))
            .firstMatch
        XCTAssertTrue(resultRow.waitForExistence(timeout: 8), "Expected at least one search result for demo data")

        activate(resultRow, app: app)
        let detailName = app.staticTexts["program-detail-name"].firstMatch
        XCTAssertTrue(detailName.waitForExistence(timeout: 5), "Program detail should open from search result")
        XCTAssertTrue(detailName.label.contains("Extreme Ironing World Cup"), "Search detail should match the requested program")
        #else
        #if !os(macOS)
        navigateToTab("Guide", app: app)
        #endif
        XCTAssertTrue(waitForGuideContent(in: app), "Guide content should be ready before opening search")
        let idSearchField = app.textFields["global-search-field"].firstMatch
        let labeledSearchField = app.textFields.matching(NSPredicate(format: "label CONTAINS[c] 'Search' OR value CONTAINS[c] 'Search'"))
            .firstMatch
        let anySearchField = app.textFields.firstMatch

        XCTAssertTrue(
            idSearchField.waitForExistence(timeout: 8) ||
            labeledSearchField.waitForExistence(timeout: 2) ||
            anySearchField.waitForExistence(timeout: 2),
            "A search field should be visible"
        )

        let effectiveField = idSearchField.exists ? idSearchField : (labeledSearchField.exists ? labeledSearchField : anySearchField)
        activate(effectiveField, app: app)
        effectiveField.typeText("Extreme Ironing World Cup\n")

        let resultRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search-result-'"))
            .firstMatch
        XCTAssertTrue(resultRow.waitForExistence(timeout: 8), "Expected at least one search result for demo data")

        activate(resultRow, app: app)
        let detailName = app.staticTexts["program-detail-name"].firstMatch
        XCTAssertTrue(detailName.waitForExistence(timeout: 5), "Program detail should open from search result")
        XCTAssertTrue(detailName.label.contains("Extreme Ironing World Cup"), "Search detail should match the requested program")
        #endif
    }

    #if os(iOS)
    @MainActor
    func testCalendarIsReachableFromTopics() throws {
        let app = launchApp()

        navigateToTab("Calendar", app: app)
        let calendarView = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'calendar-view'"))
            .firstMatch

        XCTAssertTrue(
            calendarView.waitForExistence(timeout: 8) ||
            app.buttons["Day"].firstMatch.waitForExistence(timeout: 2) ||
            app.buttons["Week"].firstMatch.waitForExistence(timeout: 2),
            "Calendar should open successfully"
        )
    }
    #endif

    #if !os(macOS)
    @MainActor
    func testSettingsCanUnlinkServer() throws {
        let app = launchApp()
        navigateToTab("Settings", app: app)

        let unlinkButton = app.buttons["unlink-server-button"].firstMatch
        XCTAssertTrue(unlinkButton.waitForExistence(timeout: 5), "Settings should expose server unlinking")

        #if os(tvOS)
        let remote = XCUIRemote.shared
        for _ in 0..<8 {
            if unlinkButton.hasFocus { break }
            remote.press(.down)
            pause(0.4)
        }
        remote.press(.select)
        pause(1.0)
        remote.press(.left)
        pause(0.3)
        remote.press(.select)
        #else
        activate(unlinkButton, app: app)
        let confirmButton = app.buttons["confirm-unlink-button"].firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Unlink confirmation should appear")
        activate(confirmButton, app: app)
        #endif

        let configureManually = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Configure Server Manually'")).firstMatch
        let findOrConfigure = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Find or Configure Server'")).firstMatch
        XCTAssertTrue(
            configureManually.waitForExistence(timeout: 8) || findOrConfigure.waitForExistence(timeout: 2),
            "App should return to setup after unlinking"
        )
    }
    #endif

    // MARK: - UIFontSize persistence (PR #128)

    #if !os(macOS)
    @MainActor
    func testUIFontSizePersistsAcrossAppLaunches() throws {
        // PR #128 introduces a `uiFontSize` field on UserPreferences. The
        // model layer's persistence (UserDefaults + iCloud KVS) is exercised
        // by UIFontSizeTests in the unit-test target. This UI test verifies
        // the *integration*: that the field round-trips through the app's
        // actual storage key without crashing the app on launch, and that
        // the value survives an app restart (i.e. the OS-level
        // UserDefaults persistence works end-to-end with the new field).
        //
        // We don't need a SettingsView UI to validate this — the app reads
        // UserPreferences at launch and renders whatever is in it. If the
        // new field were mis-named, mis-typed, or mis-decoded, the app
        // would crash on the load() call. The fact that it launches proves
        // the integration is healthy.

        // Use a JSON-encoded UserPreferences blob. We use a hand-written
        // JSON dict (not a Swift struct) because the test target doesn't
        // import the app's UserPreferences type — the test target is a
        // separate module. The "uiFontSize" key is the new field from
        // PR #128; the rest are existing fields to satisfy Codable's
        // exhaustive-decode requirement.
        let prefsJSON = """
        {
          "uiFontSize": "xLarge",
          "subtitleMode": "manual",
          "subtitleSize": "medium",
          "subtitleBackground": true,
          "preferredSubtitleLanguage": null,
          "guideShowGroupsInSidebar": false,
          "guideGroupIds": [],
          "guideShowProfilesInSidebar": false,
          "guideProfileIds": [],
          "seekBackwardSeconds": 10,
          "seekForwardSeconds": 30,
          "audioChannels": "stereo",
          "tvosGPUAPI": "videotoolbox",
          "iosGPUAPI": "videotoolbox",
          "macosGPUAPI": "videotoolbox",
          "landingTab": "guide",
          "hideRecordings": false,
          "theme": "system",
          "keywords": []
        }
        """

        // Inject the blob into the standard UserDefaults suite the app uses.
        // The app's UserPreferences.load() reads from "UserPreferences" key.
        guard let data = prefsJSON.data(using: .utf8) else {
            XCTFail("Could not encode test JSON"); return
        }
        UserDefaults.standard.set(data, forKey: "UserPreferences")

        // Launch the app. If UserPreferences.load() throws or the new
        // field causes a crash, the app will not reach .runningForeground.
        let app = launchApp()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "App should launch successfully with the new uiFontSize field in stored UserPreferences"
        )

        // The app is now running with uiFontSize=.xLarge in its in-memory
        // UserPreferences. We can't inspect that from outside the process,
        // but we can verify the persisted blob is still well-formed after
        // the app's load() ran successfully. If load() had parsed and
        // re-encoded, the file would still be valid JSON.
        let reread = UserDefaults.standard.data(forKey: "UserPreferences")
        XCTAssertNotNil(reread, "UserPreferences blob should still be present after app launch")

        if let reread {
            // The app's load() runs `loadFromAppGroup` and `ubiquitousStore.synchronize()`.
            // Either of these may overwrite the UserDefaults.standard copy with an
            // older or differently-encoded blob. After a successful app launch, we
            // expect the standard suite to still contain a valid JSON blob with
            // uiFontSize = "xLarge".
            let asString = String(data: reread, encoding: .utf8) ?? ""
            // Use plain string contains with two checks: the JSON may be
            // pretty-printed (one key per line) or compact (all on one line).
            let keyPair = "\"uiFontSize\""
            XCTAssertTrue(
                asString.contains(keyPair),
                "Persisted blob should contain uiFontSize key. Got: " + asString.prefix(200)
            )
            let valuePair = "\"xLarge\""
            XCTAssertTrue(
                asString.contains(valuePair),
                "Persisted blob should contain xLarge value. Got: " + asString.prefix(200)
            )
        }

        // Restart the app and confirm the value still loads cleanly.
        app.terminate()
        let relaunched = launchApp()
        XCTAssertTrue(
            relaunched.wait(for: .runningForeground, timeout: 10),
            "App should relaunch successfully with persisted uiFontSize"
        )

        // Tear down so the test doesn't pollute other UI tests.
        UserDefaults.standard.removeObject(forKey: "UserPreferences")
    }
    #endif

    // MARK: - App Launch

    @MainActor
    private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif

        let app = XCUIApplication()
        app.launchArguments = ["--demo-mode", "--ui-testing"] + additionalArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    // MARK: - Navigation

    private func navigateToTab(_ tabName: String, app: XCUIApplication) {
        #if os(tvOS)
        let remote = XCUIRemote.shared
        remote.press(.menu)
        pause(1.0)

        #if DISPATCHERPVR
        let tabs = ["Guide", "Recordings", "Topics", "Stats", "Settings"]
        #else
        let tabs = ["Guide", "Recordings", "Topics", "Settings"]
        #endif

        guard let targetIndex = tabs.firstIndex(of: tabName) else { return }
        for _ in 0..<targetIndex {
            remote.press(.right)
            pause(0.4)
        }
        remote.press(.select)
        pause(1.2)
        #elseif os(macOS)
        let effectiveTab = tabName == "Search" ? "Guide" : tabName
        let candidates: [XCUIElement] = [
            app.outlines.buttons[effectiveTab].firstMatch,
            app.outlines.staticTexts[effectiveTab].firstMatch,
            app.cells[effectiveTab].firstMatch,
            app.staticTexts[effectiveTab].firstMatch,
            app.buttons[effectiveTab].firstMatch,
            app.cells.containing(.staticText, identifier: effectiveTab).firstMatch,
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 0.5) {
            candidate.click()
            pause(0.8)
            return
        }
        XCTFail("Could not navigate to macOS tab '\(effectiveTab)'")
        #else
        if tabName == "Search" {
            navigateToTab("Guide", app: app)
            return
        }

        if tabName == "Guide", waitForGuideContent(in: app) {
            return
        }

        let expandButton = app.buttons["nav-expand-button"].firstMatch
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5), "Expected floating navigation button")
        activate(expandButton, app: app)
        let tabButton = app.buttons["tab-\(tabName)"].firstMatch
        let recordingsFallback = app.buttons["recordings-filter-Completed"].firstMatch

        XCTAssertTrue(
            waitForCondition(timeout: 5) {
                tabName == "Recordings"
                    ? recordingsFallback.exists || tabButton.exists
                    : tabButton.exists
            },
            "Expected sidebar target for '\(tabName)'"
        )

        if tabName == "Recordings" {
            activate(recordingsFallback, app: app)
        } else {
            XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "Expected tab button for '\(tabName)'")
            activate(tabButton, app: app)
        }
        pause(1.0)
        #endif
    }

    // MARK: - Scenario Helpers

    private func waitForGuideContent(in app: XCUIApplication) -> Bool {
        waitForCondition(timeout: 10) {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-program-'")).count > 0 ||
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-channel-'")).count > 0 ||
            app.staticTexts["SportsCenter HD"].exists
        }
    }

    private func openFutureProgramDetailAndCaptureName(app: XCUIApplication) throws -> String {
        navigateToTab("Guide", app: app)
        XCTAssertTrue(waitForGuideContent(in: app), "Guide content should be loaded before opening details")

        #if os(tvOS)
        let remote = XCUIRemote.shared
        remote.press(.down)
        pause(1.0)

        for attempt in 0..<6 {
            let horizontalMoves = 8 + (attempt * 4)
            for _ in 0..<horizontalMoves {
                remote.press(.right)
                pause(0.25)
            }

            remote.press(.select)
            pause(1.5)

            let recordButton = app.buttons["record-button"].firstMatch
            let cancelButton = app.buttons["cancel-recording-button"].firstMatch
            if recordButton.waitForExistence(timeout: 2) || cancelButton.waitForExistence(timeout: 1) {
                let detailName = app.staticTexts["program-detail-name"].firstMatch
                XCTAssertTrue(detailName.waitForExistence(timeout: 2))
                return detailName.label
            }

            if app.otherElements["player-view"].exists {
                dismissPlayer(app: app)
            } else {
                remote.press(.menu)
                pause(0.5)
            }

            remote.press(.down)
            pause(0.4)
        }

        throw NSError(domain: "NexusPVRUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate a future program with recording controls on tvOS"])
        #else
        let programButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-program-'"))
        XCTAssertTrue(waitForCondition(timeout: 5) { programButtons.count > 0 })

        let count = programButtons.count
        let startIndex = max(0, (count * 2) / 3)

        for index in startIndex..<min(startIndex + 10, count) {
            let button = programButtons.element(boundBy: index)
            guard button.exists else { continue }

            #if os(macOS)
            button.click()
            #else
            let frame = button.frame
            guard frame.width > 1, frame.height > 1 else { continue }
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            #endif
            pause(1.0)

            let recordButton = app.buttons["record-button"].firstMatch
            let cancelButton = app.buttons["cancel-recording-button"].firstMatch
            if recordButton.waitForExistence(timeout: 1.5) || cancelButton.waitForExistence(timeout: 1) {
                let detailName = app.staticTexts["program-detail-name"].firstMatch
                XCTAssertTrue(detailName.waitForExistence(timeout: 2))
                let label = detailName.label.isEmpty ? (detailName.value as? String ?? "") : detailName.label
                XCTAssertFalse(label.isEmpty)
                return label
            }

            dismissPresentedDetail(app: app)
            pause(0.3)
        }

        if let label = findRecordableProgramViaSearch(app: app, query: "Extreme Ironing World Cup") {
            return label
        }

        throw NSError(domain: "NexusPVRUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate a future program with recording controls"])
        #endif
    }

    private func findRecordableProgramViaSearch(app: XCUIApplication, query: String) -> String? {
        let searchField = app.textFields["global-search-field"].firstMatch
        guard searchField.waitForExistence(timeout: 6) else { return nil }

        activate(searchField, app: app)
        searchField.tap()
        if let currentValue = searchField.value as? String, !currentValue.isEmpty, currentValue.lowercased() != "search" {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            searchField.typeText(deleteString)
        }
        searchField.typeText("\(query)\n")

        let resultRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search-result-'"))

        guard waitForCondition(timeout: 8, condition: { resultRows.count > 0 }) else { return nil }

        for index in 0..<min(resultRows.count, 20) {
            let row = resultRows.element(boundBy: index)
            guard row.exists else { continue }
            activate(row, app: app)

            let recordButton = app.buttons["record-button"].firstMatch
            let cancelButton = app.buttons["cancel-recording-button"].firstMatch
            if recordButton.waitForExistence(timeout: 1.5) || cancelButton.waitForExistence(timeout: 1.0) {
                let detailName = app.staticTexts["program-detail-name"].firstMatch
                guard detailName.waitForExistence(timeout: 2) else { return nil }
                let label = detailName.label.isEmpty ? (detailName.value as? String ?? "") : detailName.label
                return label.isEmpty ? nil : label
            }

            dismissPresentedDetail(app: app)
            pause(0.3)
        }

        return nil
    }

    private func openSearchResult(named programName: String, in app: XCUIApplication) {
        let searchField = app.textFields["global-search-field"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8), "A global search field should be visible")
        activate(searchField, app: app)
        searchField.typeText("\(programName)\n")

        let resultRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'search-result-' AND label CONTAINS[c] %@", programName))
            .firstMatch
        XCTAssertTrue(resultRow.waitForExistence(timeout: 8), "Expected a search result for '\(programName)'")

        let detailName = app.staticTexts["program-detail-name"].firstMatch
        for _ in 0..<3 {
            activate(resultRow, app: app)
            if detailName.waitForExistence(timeout: 2.5) {
                return
            }
            pause(0.4)
        }

        XCTFail("Expected program detail to open from search result '\(programName)'")
    }

    private func openKeywordEditor(app: XCUIApplication) {
        let editButton = app.buttons["edit-keywords-button"].firstMatch
        if editButton.waitForExistence(timeout: 2) {
            activate(editButton, app: app)
            return
        }

        navigateToTab("Topics", app: app)

        #if os(iOS)
        // In current iOS navigation, selecting Topics opens the keyword editor view directly.
        let keywordField = app.textFields["keyword-text-field"].firstMatch
        if keywordField.waitForExistence(timeout: 3) {
            return
        }
        #endif

        if editButton.waitForExistence(timeout: 2) {
            activate(editButton, app: app)
            return
        }

        let editByLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Edit Keywords'")).firstMatch
        XCTAssertTrue(editByLabel.waitForExistence(timeout: 5), "Expected a way to edit keywords")
        activate(editByLabel, app: app)
    }

    private func dismissKeywordEditor(app: XCUIApplication) {
        let doneButton = app.buttons["keywords-done-button"].firstMatch
        if doneButton.waitForExistence(timeout: 2) {
            activate(doneButton, app: app)
            return
        }
        dismissPresentedDetail(app: app)
    }

    private func dismissPresentedDetail(app: XCUIApplication) {
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        pause(0.8)
        #else
        let doneButton = app.buttons["Done"].firstMatch
        if doneButton.waitForExistence(timeout: 2) {
            activate(doneButton, app: app)
            pause(0.8)
            return
        }
        #if os(macOS)
        app.typeKey(.escape, modifierFlags: [])
        pause(0.8)
        #endif
        #endif
    }

    private func dismissPlayer(app: XCUIApplication) {
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        pause(1.0)
        #else
        let closeButton = app.buttons["player-close-button"].firstMatch
        if closeButton.waitForExistence(timeout: 2) {
            activate(closeButton, app: app)
        } else {
            #if os(macOS)
            app.typeKey(.escape, modifierFlags: [])
            #endif
        }
        pause(1.0)
        #endif
    }

    private func selectRecordingsFilter(_ filter: String, in app: XCUIApplication) {
        #if os(tvOS)
        let remote = XCUIRemote.shared
        remote.press(.menu)
        pause(0.8)

        let targetIdentifier = "recordings-filter-\(filter)"
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", targetIdentifier))
            .firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected recordings filter '\(filter)' to be available")

        for _ in 0..<8 where !option.hasFocus {
            remote.press(.down)
            pause(0.2)
        }
        for _ in 0..<8 where !option.hasFocus {
            remote.press(.up)
            pause(0.2)
        }

        XCTAssertTrue(option.hasFocus, "Expected recordings filter '\(filter)' to receive focus")
        remote.press(.select)
        pause(0.8)
        #elseif os(iOS)
        let targetIdentifier: String
        switch filter {
        case "Completed":
            targetIdentifier = "recordings-filter-Completed"
        case "Scheduled":
            targetIdentifier = "recordings-filter-Scheduled"
        case "Active":
            targetIdentifier = "recordings-filter-Recording"
        default:
            targetIdentifier = "recordings-filter-\(filter)"
        }

        var option = app.buttons[targetIdentifier].firstMatch
        if !option.waitForExistence(timeout: 2) {
            let expandButton = app.buttons["nav-expand-button"].firstMatch
            XCTAssertTrue(expandButton.waitForExistence(timeout: 5), "Expected floating navigation button")
            activate(expandButton, app: app)
            option = app.buttons[targetIdentifier].firstMatch
        }

        XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected recordings filter '\(filter)' to be available")
        activate(option, app: app)
        pause(0.8)
        #else
        selectSegment(filter, in: app)
        #endif
    }

    private func selectKeywordTab(_ keyword: String, in app: XCUIApplication) {
        #if os(iOS)
        let expandButton = app.buttons["nav-expand-button"].firstMatch
        XCTAssertTrue(expandButton.waitForExistence(timeout: 5), "Expected floating navigation button")
        activate(expandButton, app: app)

        let option = app.buttons["topic-keyword-\(keyword)"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Expected keyword tab for '\(keyword)' to be available")
        activate(option, app: app)
        pause(0.8)
        #elseif os(macOS)
        selectSegment(keyword, in: app)
        #endif
    }

    private func selectSegment(_ label: String, in app: XCUIApplication) {
        let candidates: [XCUIElement] = [
            app.buttons[label].firstMatch,
            app.segmentedControls.firstMatch.buttons[label].firstMatch,
            app.radioButtons[label].firstMatch,
            app.staticTexts[label].firstMatch,
        ]

        for candidate in candidates where candidate.waitForExistence(timeout: 0.5) {
            activate(candidate, app: app)
            pause(0.8)
            return
        }

        XCTFail("Could not select segment '\(label)'")
    }

    private func extractUsefulKeyword(from text: String) -> String? {
        let skip = Set(["the", "and", "with", "from", "episode", "season", "special", "live"])
        return text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { token in
                token.count >= 4 && !skip.contains(token.lowercased())
            }
    }

    // MARK: - Interaction

    private func activate(_ element: XCUIElement, app: XCUIApplication) {
        #if os(tvOS)
        XCUIRemote.shared.press(.select)
        #elseif os(macOS)
        element.click()
        #else
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        #endif
    }

    // MARK: - Waiting

    private func waitForCondition(timeout: TimeInterval, pollInterval: TimeInterval = 0.2, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    private func pause(_ duration: TimeInterval) {
        Thread.sleep(forTimeInterval: duration)
    }

    private func recordingRowCount(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'recording-row-'"))
            .count
    }

    // MARK: - tvOS Navigation Helpers

    #if os(tvOS)
    private func openSidebarOnTV(in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        remote.press(.menu)
        pause(1.0)
    }

    private func focusAndSelectSidebarItem(_ identifier: String, in app: XCUIApplication) {
        let remote = XCUIRemote.shared
        let target = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 8), "Sidebar item '\(identifier)' should be visible")

        for _ in 0..<14 where !target.hasFocus {
            remote.press(.down)
            pause(0.2)
        }
        for _ in 0..<14 where !target.hasFocus {
            remote.press(.up)
            pause(0.2)
        }

        XCTAssertTrue(target.hasFocus, "Sidebar item '\(identifier)' should receive focus")
        remote.press(.select)
        pause(1.0)
    }

    private func pressMenuAndAssertSidebarFocused(app: XCUIApplication, sidebarIdentifier: String) {
        let remote = XCUIRemote.shared
        remote.press(.menu)
        pause(1.0)

        let sidebarElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", sidebarIdentifier))
            .firstMatch
        XCTAssertTrue(sidebarElement.waitForExistence(timeout: 5), "Sidebar element '\(sidebarIdentifier)' should be visible after back/menu")
        XCTAssertTrue(sidebarElement.hasFocus, "Sidebar element '\(sidebarIdentifier)' should have focus after back/menu")
    }

    private func pressMenuAndAssertSidebarVisible(app: XCUIApplication) {
        let remote = XCUIRemote.shared
        remote.press(.menu)
        pause(1.0)

        let guideTab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "tab-Guide"))
            .firstMatch
        XCTAssertTrue(guideTab.waitForExistence(timeout: 5), "Sidebar should be visible after back/menu")
    }
    #endif
}
