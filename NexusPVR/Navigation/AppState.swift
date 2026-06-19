//
//  AppState.swift
//  nextpvr-apple-client
//
//  Global application state
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    let isUITesting: Bool = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    /// Test-only override for the initial landing tab. When set, this takes
    /// precedence over any persisted `UserPreferences` so tests can be
    /// deterministic regardless of what's stored on disk or in the iCloud
    /// KV store. Always nil in production. Mirrors the
    /// `UserPreferences.demoStore` pattern already used in the codebase.
    nonisolated(unsafe) static var testLandingTabOverride: LandingTabOption?

    @Published var selectedTab: Tab = AppState.initialLandingTab()
    @Published var searchQuery: String = ""
    @Published var guideChannelFilter: String = ""
    @Published var guideGroupFilter: Int? = nil
    @Published var guideProfileFilter: Int? = nil
    @Published var isShowingPlayer = false

    #if os(iOS)
    /// Whether the floating bottom bar should be hidden (e.g. while scrolling down in the guide)
    @Published var isBottomBarHidden = false
    #endif

    // Topic picker state (shared between TopicsView and iOS nav bar)
    @Published var topicKeywords: [String] = []
    @Published var topicKeywordMatchCounts: [String: Int] = [:]
    @Published var selectedTopicKeyword: String = ""
    @Published var showingKeywordsEditor = false
    @Published var showingCalendar = false

    // Recordings filter state (shared between RecordingsListView and iOS nav bar)
    @Published var recordingsFilter: RecordingsFilter = .completed
    @Published var recordingsFilterUserOverride = false
    @Published var activeRecordingCount = 0
    @Published var recordingsSeriesItems: [RecordingsSeriesItem] = []
    @Published var recordingsSeriesIsLoading = false
    @Published var selectedRecordingsSeriesName: String = ""
    @Published var showingRecordingsSeriesList = false
    var recordingsHasActive: Bool { activeRecordingCount > 0 }
    var hasSelectedRecordingsSeries: Bool { !selectedRecordingsSeriesName.isEmpty }
    @Published var currentlyPlayingURL: URL?
    @Published var currentlyPlayingTitle: String?
    @Published var currentlyPlayingRecordingId: Int?
    @Published var currentlyPlayingResumePosition: Int?
    @Published var currentlyPlayingChannelId: Int?
    @Published var currentlyPlayingChannelName: String?
    @Published var currentlyPlayingIsRecordingInProgress = false
    @Published var currentlyPlayingRecordingStartTime: Date?

    // Navigation state
    @Published var selectedChannel: Channel?
    @Published var selectedProgram: Program?
    @Published var selectedRecording: Recording?
    #if os(tvOS)
    /// When true, the global tvOS escape handler must not move focus to the sidebar.
    @Published var tvosBlocksSidebarExitCommand = false
    /// Settings-specific exit orchestration for tvOS.
    @Published var tvosSettingsHasPopup = false
    @Published var tvosSettingsShowingEventLog = false
    @Published var tvosSettingsDismissPopupRequest = 0
    @Published var tvosSettingsDismissEventLogRequest = 0
    @Published var tvosPlayerSettingsPanelOpen = false
    #endif

    // Alert state
    @Published var alertMessage: String?
    @Published var isShowingAlert = false

    #if DISPATCHERPVR
    // Active stream count for badge
    @Published var activeStreamCount = 0
    // M3U account error indicator for badge
    @Published var hasM3UErrors = false
    /// User role level from Dispatcharr (0=Streamer, 1=Standard, 10=Admin)
    @Published var userLevel: Int = 10 {
        didSet { reconcileSelectedTabForCurrentAccess() }
    }
    #else
    /// NexusPVR users always have full access
    var userLevel: Int { 10 }
    #endif
    #if DISPATCHERPVR
    /// Whether the current user can create/modify/delete recordings
    var canManageRecordings: Bool { userLevel >= 10 }
    private var streamCountTask: Task<Void, Never>?

    func startStreamCountPolling(client: DispatcherClient) {
        stopStreamCountPolling()
        // Streamer users (output-only) have no access to proxy/m3u APIs
        guard !client.useOutputEndpoints else { return }
        streamCountTask = Task { [weak self] in
            while !Task.isCancelled {
                // Skip polling while player is active to reduce network/CPU during playback
                if self?.isShowingPlayer != true {
                    do {
                        let status = try await client.getProxyStatus()
                        let newCount = status.count ?? status.channels?.count ?? 0
                        self?.activeStreamCount = newCount
                    } catch {
                        // Silently ignore - badge just won't update
                    }
                    do {
                        let accounts = try await client.getM3UAccounts()
                        let activeAccounts = accounts.filter { $0.isActive && !$0.locked }
                        let hasErrors = activeAccounts.contains { $0.status != "success" }
                        self?.hasM3UErrors = hasErrors
                    } catch {
                        // Silently ignore
                    }
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopStreamCountPolling() {
        streamCountTask?.cancel()
        streamCountTask = nil
    }
    #endif

    #if !TOPSHELF_EXTENSION
    private var recordingsActivityTask: Task<Void, Never>?

    func startRecordingsActivityPolling(client: PVRClient) {
        stopRecordingsActivityPolling()
        recordingsActivityTask = Task { [weak self] in
            while !Task.isCancelled {
                // Skip polling while player is active to reduce network/CPU during playback
                if self?.isShowingPlayer != true {
                    await self?.refreshRecordingsActivity(client: client)
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopRecordingsActivityPolling() {
        recordingsActivityTask?.cancel()
        recordingsActivityTask = nil
    }

    func refreshRecordingsActivity(client: PVRClient) async {
        if !client.isConfigured {
            activeRecordingCount = 0
            return
        }
        do {
            if !client.isAuthenticated {
                try await client.authenticate()
            }
            let (_, recording, _) = try await client.getAllRecordings()
            activeRecordingCount = recording.count
        } catch {
            // Silently ignore transient errors; keep last known badge state.
        }
    }

    func refreshRecordingsSidebarData(client: PVRClient) async {
        if !client.isConfigured {
            activeRecordingCount = 0
            recordingsSeriesItems = []
            recordingsSeriesIsLoading = false
            return
        }

        recordingsSeriesIsLoading = true
        defer { recordingsSeriesIsLoading = false }

        do {
            if !client.isAuthenticated {
                try await client.authenticate()
            }
            let (completed, recording, scheduled) = try await client.getAllRecordings()
            activeRecordingCount = recording.count

            let grouped = Dictionary(grouping: (completed + recording + scheduled).filter { $0.seriesInfo != nil }) {
                $0.seriesInfo!.seriesName
            }
            recordingsSeriesItems = grouped
                .map { name, recordings in
                    RecordingsSeriesItem(name: name, count: recordings.count)
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // Keep previous values on transient failures.
        }
    }
    #endif

    func showAlert(_ message: String) {
        alertMessage = message
        isShowingAlert = true
    }

    func setRecordingsFilter(_ filter: RecordingsFilter, userInitiated: Bool) {
        recordingsFilter = filter
        selectedRecordingsSeriesName = ""
        showingRecordingsSeriesList = false
        if userInitiated {
            recordingsFilterUserOverride = true
        }
    }

    // MARK: - Landing Tab

    /// Resolve the initial landing tab. Honors `testLandingTabOverride` if
    /// set (used by tests for deterministic behavior), otherwise falls back
    /// to the persisted `UserPreferences` value. Unknown / future raw
    /// values fall back to `.guide` so the app still launches cleanly
    /// after a downgrade or corrupted preference blob.
    static func initialLandingTab() -> Tab {
        if let override = testLandingTabOverride {
            return tab(for: override)
        }
        let prefs = UserPreferences.load()
        return tab(for: prefs.landingTab)
    }

    /// Map a `LandingTabOption` to the corresponding `Tab`.
    /// The mapping is one-way and centralized so that preferences can be
    /// applied consistently across all platforms and launch paths.
    static func tab(for option: LandingTabOption) -> Tab {
        switch option {
        case .guide: return .guide
        case .channels: return .channels
        case .completedRecordings: return .recordings
        }
    }

    /// Whether a landing option's target tab is available to the current
    /// user. The Completed Recordings landing requires `userLevel >= 1`
    /// (recordings access); the other landings are always available.
    /// Used by both the Settings picker (to filter out unavailable
    /// options) and `applyLandingTab` (to redirect to Guide if needed).
    static func isLandingOptionAvailable(
        _ option: LandingTabOption,
        forUserLevel userLevel: Int
    ) -> Bool {
        switch option {
        case .guide, .channels:
            return true
        case .completedRecordings:
            return userLevel >= 1
        }
    }

    /// Keep the selected tab in sync with the user's current access level.
    /// Dispatcharr resolves `userLevel` after launch, so a persisted landing
    /// tab can briefly select Recordings before the app learns the current
    /// user is a Streamer. Redirect in that case so the UI never stays on a
    /// tab that the sidebars have hidden.
    func reconcileSelectedTabForCurrentAccess() {
        if selectedTab == .recordings && userLevel < 1 {
            selectedTab = .guide
        }
    }

    /// Convenience helper used by settings UI when applying a new landing
    /// preference: navigates to the right tab and, for `.completedRecordings`,
    /// forces the completed filter without setting the user-override flag.
    /// If the requested option is not available for the current user
    /// (e.g. Completed Recordings for a Dispatcharr streamer without
    /// recordings access), falls back to the Guide tab so the user never
    /// lands on a hidden/non-existent destination.
    func applyLandingTab(_ option: LandingTabOption) {
        let resolved: LandingTabOption
        if Self.isLandingOptionAvailable(option, forUserLevel: userLevel) {
            resolved = option
        } else {
            resolved = .guide
        }
        let target = Self.tab(for: resolved)
        selectedTab = target
        if resolved == .completedRecordings {
            recordingsFilter = .completed
            selectedRecordingsSeriesName = ""
            showingRecordingsSeriesList = false
            // The user explicitly chose this landing — do not mark as override.
            recordingsFilterUserOverride = false
        }
    }

    func selectRecordingsSeries(named seriesName: String, userInitiated: Bool) {
        selectedRecordingsSeriesName = seriesName
        showingRecordingsSeriesList = false
        if userInitiated {
            recordingsFilterUserOverride = true
        }
    }

    func showRecordingsSeriesMenu(userInitiated: Bool) {
        selectedRecordingsSeriesName = ""
        showingRecordingsSeriesList = true
        if userInitiated {
            recordingsFilterUserOverride = true
        }
    }

    func playStream(
        url: URL,
        title: String,
        recordingId: Int? = nil,
        resumePosition: Int? = nil,
        channelId: Int? = nil,
        channelName: String? = nil,
        isRecordingInProgress: Bool = false,
        recordingStartTime: Date? = nil
    ) {
        #if DEBUG
        let effectiveURL: URL
        if UserDefaults.standard.bool(forKey: "debugStreamEnabled"),
           let debugURL = UserDefaults.standard.string(forKey: "debugStreamURL"),
           let override = URL(string: debugURL) {
            effectiveURL = override
            print("DEBUG: stream URL overridden to \(debugURL)")
        } else {
            effectiveURL = url
        }
        #else
        let effectiveURL = url
        #endif
        currentlyPlayingURL = effectiveURL
        currentlyPlayingTitle = title
        currentlyPlayingRecordingId = recordingId
        currentlyPlayingResumePosition = resumePosition
        currentlyPlayingChannelId = channelId
        currentlyPlayingChannelName = channelName
        currentlyPlayingIsRecordingInProgress = isRecordingInProgress
        currentlyPlayingRecordingStartTime = recordingStartTime
        isShowingPlayer = true
    }

    func playStream(url: URL, title: String, channelId: Int, channelName: String) {
        var history = WatchHistory.load()
        history.recordChannelPlay(channelId: channelId, channelName: channelName)
        history.save()
        playStream(
            url: url,
            title: title,
            recordingId: nil,
            resumePosition: nil,
            channelId: channelId,
            channelName: channelName
        )
    }

    func stopPlayback() {
        isShowingPlayer = false
        currentlyPlayingURL = nil
        currentlyPlayingTitle = nil
        currentlyPlayingRecordingId = nil
        currentlyPlayingResumePosition = nil
        currentlyPlayingChannelId = nil
        currentlyPlayingChannelName = nil
        currentlyPlayingIsRecordingInProgress = false
        currentlyPlayingRecordingStartTime = nil
    }

    /// Dismiss the player UI without clearing playback state (used for PiP).
    func dismissPlayer() {
        isShowingPlayer = false
    }
}
