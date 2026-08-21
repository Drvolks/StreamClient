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
    /// Persists the calendar's visible day while macOS temporarily replaces
    /// navigation with PlayerView during catch-up playback.
    @Published var calendarSelectedDate = Date()

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
    /// Dispatcharr catch-up (timeshift) session id (#119), when the current
    /// stream is archived playback rather than live/recording. Revoked by
    /// `PlayerView` on teardown — see `endCatchupSessionIfNeeded()`.
    @Published var currentlyPlayingCatchupSessionId: String?
    /// Guide time that launched the current catch-up playback. Unlike the
    /// session id, this intentionally survives `stopPlayback()` long enough
    /// for a reconstructed macOS guide to consume and restore it.
    private(set) var catchupGuideReturnTime: Date?

    // Navigation state
    @Published var selectedChannel: Channel?
    @Published var selectedProgram: Program?
    @Published var selectedRecording: Recording?
    #if DISPATCHERPVR
    /// Channel whose archive browser is opened from the Channels page.
    /// Global navigation state lets macOS restore the destination after PlayerView
    /// temporarily replaces the entire navigation hierarchy.
    @Published var selectedCatchupChannel: Channel?
    #endif
    #if os(tvOS)
    /// When true, the global tvOS escape handler must not move focus to the sidebar.
    @Published var tvosBlocksSidebarExitCommand = false
    /// Settings-specific exit orchestration for tvOS.
    @Published var tvosSettingsHasPopup = false
    @Published var tvosSettingsShowingEventLog = false
    @Published var tvosSettingsDismissPopupRequest = 0
    @Published var tvosSettingsDismissEventLogRequest = 0
    @Published var tvosPlayerSettingsPanelOpen = false
    /// Incremented when the sidebar hands focus to the Channels page so the
    /// grid always starts on the first channel card (#111).
    @Published var tvosChannelsFocusFirstRequest = 0
    #endif

    // Alert state
    @Published var alertMessage: String?
    @Published var isShowingAlert = false

    /// True while a stream URL is being resolved, before the player can open.
    /// For NextPVR live TV this covers starting the server-side timeshift buffer
    /// and waiting for it to fill, which takes a few seconds — long enough that
    /// without feedback it looks like the tap did nothing.
    @Published var isPreparingStream = false

    #if DISPATCHERPVR
    // Active stream count for badge
    @Published var activeStreamCount = 0
    // M3U account error indicator for badge
    @Published var hasM3UErrors = false
    /// User role level from Dispatcharr (0=Streamer, 1=Standard, 10=Admin)
    @Published var userLevel: Int = 10 {
        didSet { reconcileSelectedTabForCurrentAccess() }
    }

    /// Most recent `EnvironmentSettings` payload from
    /// `GET /api/core/settings/env/`. Nil until the first poll completes, or
    /// when running in demo / output-only mode (where the endpoint is not
    /// reachable). When nil and `environmentAvailable` is false, the UI
    /// shows "not available on this server version"; when nil and
    /// `environmentAvailable` is true, the UI shows a "loading" placeholder.
    /// (#112)
    @Published var environmentSettings: EnvironmentSettings?
    #else
    /// NexusPVR users always have full access
    var userLevel: Int { 10 }
    #endif

    /// Whether the user chose to hide all recording features in Settings (#110).
    @Published var hideRecordings: Bool = UserPreferences.load().hideRecordings {
        didSet { reconcileSelectedTabForCurrentAccess() }
    }

    /// The appearance the user chose in Settings (#108). Applied at the root
    /// of the scene so a change takes effect immediately, without a relaunch.
    @Published var theme: AppTheme = UserPreferences.load().theme

    #if os(tvOS)
    /// The tvOS UI font size the user chose in Settings (#107).
    ///
    /// The value that fonts and metrics actually read is the
    /// `Theme.uiFontSize` global — `Font` extensions are static, so they
    /// can't observe an environment object. This published mirror exists
    /// to *invalidate* the view tree: every view holding `appState` as an
    /// `@EnvironmentObject` re-evaluates its body when this changes, and
    /// picks up the new global on the way through. That applies the new
    /// size live without an `.id()` bump at the root, which would reset
    /// navigation and bounce the user out of Settings mid-change.
    @Published var uiFontSize: UIFontSize = UserPreferences.load().uiFontSize {
        didSet { Theme.uiFontSize = uiFontSize }
    }
    #endif

    /// Whether recording-related UI (tabs, menus, buttons) should be shown.
    var showsRecordings: Bool { userLevel >= 1 && !hideRecordings }

    #if DISPATCHERPVR
    /// Whether the current user can create/modify/delete recordings
    var canManageRecordings: Bool { userLevel >= 10 && !hideRecordings }
    #else
    /// Whether the current user can create/modify/delete recordings
    var canManageRecordings: Bool { !hideRecordings }
    #endif

    #if DISPATCHERPVR
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

    /// Whether the `EnvironmentSettings` endpoint is reachable for this
    /// client. Used by the Settings UI to decide between "loading…",
    /// "not available on this server version", and the populated IP/
    /// country panel. (#112)
    var environmentAvailable: Bool {
        guard let envClient = _lastEnvClient else { return false }
        return !envClient.useOutputEndpoints
            && (!envClient.config.isDemoMode || envClient.config.isMockServer)
    }
    /// Holds the most recent client used to fetch environment settings.
    /// Tracked so `environmentAvailable` can answer without callers
    /// needing to thread the client through. (#112)
    private var _lastEnvClient: DispatcherClient?

    private var environmentSettingsTask: Task<Void, Never>?

    /// Steady-state cadence for the environment endpoint. The data changes
    /// rarely (only on Dispatcharr restart), so 30 s is plenty. (#112)
    static let environmentRefreshInterval: Duration = .seconds(30)

    /// Faster catch-up delays used while the server reports the IP lookup as
    /// still pending. Dispatcharr never resolves the public IP at startup: the
    /// first `GET /api/core/settings/env/` returns `ip_lookup_pending: true`
    /// and kicks off a background thread (ipify + geo lookup) that usually
    /// finishes within a couple of seconds. Polling at the steady 30 s cadence
    /// meant the UI sat on "Looking up…" long after the server had the answer,
    /// so back off gently instead — these five retries cover the first ~30 s
    /// before falling back to `environmentRefreshInterval`. (#112)
    static let environmentPendingRetryDelays: [Duration] = [
        .seconds(2), .seconds(3), .seconds(5), .seconds(8), .seconds(12)
    ]

    /// Whether the payload means "the server is still working on it", i.e. the
    /// UI is showing a placeholder and a quick re-poll is worthwhile. A nil
    /// `publicIP` counts even without the pending flag, since an older
    /// Dispatcharr may omit it while the background lookup runs.
    static func isEnvironmentLookupPending(_ env: EnvironmentSettings) -> Bool {
        guard env.ipLookupEnabled else { return false }
        return env.ipLookupPending || env.publicIP == nil
    }

    /// Refresh the server environment settings, polling quickly while the
    /// server reports the lookup as pending and settling to
    /// `environmentRefreshInterval` once it resolves. Cancels any in-flight
    /// refresh task first. (#112)
    func startEnvironmentSettingsRefresh(client: DispatcherClient) {
        stopEnvironmentSettingsRefresh()
        _lastEnvClient = client
        // Output-only deployments don't have the env endpoint. Built-in demo
        // mode is offline, but the local mock fixture exposes the endpoint.
        guard !client.useOutputEndpoints,
              !client.config.isDemoMode || client.config.isMockServer else {
            environmentSettings = nil
            return
        }
        environmentSettingsTask = Task { [weak self] in
            var pendingRetry = 0
            while !Task.isCancelled {
                var delay = Self.environmentRefreshInterval
                // Skip during playback to reduce network chatter.
                if self?.isShowingPlayer != true {
                    do {
                        let result = try await client.getEnvironmentSettings()
                        self?.environmentSettings = result
                        if let result, Self.isEnvironmentLookupPending(result),
                           pendingRetry < Self.environmentPendingRetryDelays.count {
                            delay = Self.environmentPendingRetryDelays[pendingRetry]
                            pendingRetry += 1
                        } else {
                            pendingRetry = 0
                        }
                    } catch {
                        // Silently ignore — the UI keeps showing the last
                        // good value. Nil is treated as "still loading" if
                        // the endpoint is reachable.
                    }
                }
                try? await Task.sleep(for: delay)
            }
        }
    }

    func stopEnvironmentSettingsRefresh() {
        environmentSettingsTask?.cancel()
        environmentSettingsTask = nil
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
        if prefs.hideRecordings && prefs.landingTab == .completedRecordings {
            return .guide
        }
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
        #if DISPATCHERPVR
        case .stats: return .stats
        #endif
        }
    }

    /// Whether a landing option's target tab is available to the current
    /// user. The Completed Recordings landing requires `userLevel >= 1`
    /// (recordings access) and the Status landing (Dispatcharr only)
    /// requires `userLevel >= 1`; the other landings are always available.
    /// Used by both the Settings picker (to filter out unavailable
    /// options) and `applyLandingTab` (to redirect to Guide if needed).
    static func isLandingOptionAvailable(
        _ option: LandingTabOption,
        forUserLevel userLevel: Int,
        hideRecordings: Bool = false
    ) -> Bool {
        switch option {
        case .guide, .channels:
            return true
        case .completedRecordings:
            return userLevel >= 1 && !hideRecordings
        #if DISPATCHERPVR
        case .stats:
            return userLevel >= 1
        #endif
        }
    }

    /// Keep the selected tab in sync with the user's current access level.
    /// Dispatcharr resolves `userLevel` after launch, so a persisted landing
    /// tab can briefly select Recordings before the app learns the current
    /// user is a Streamer. Redirect in that case so the UI never stays on a
    /// tab that the sidebars have hidden.
    func reconcileSelectedTabForCurrentAccess() {
        if selectedTab == .recordings && !showsRecordings {
            selectedTab = .guide
        }
        #if DISPATCHERPVR
        if selectedTab == .stats && userLevel < 1 {
            selectedTab = .guide
        }
        #endif
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
        if Self.isLandingOptionAvailable(option, forUserLevel: userLevel, hideRecordings: hideRecordings) {
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

    /// Runs stream-URL resolution behind the "starting stream" indicator. Clears
    /// the indicator however the work ends, so a thrown error can't leave it stuck.
    func preparingStream<T>(_ work: () async throws -> T) async rethrows -> T {
        isPreparingStream = true
        defer { isPreparingStream = false }
        return try await work()
    }

    func playStream(
        url: URL,
        title: String,
        recordingId: Int? = nil,
        resumePosition: Int? = nil,
        channelId: Int? = nil,
        channelName: String? = nil,
        isRecordingInProgress: Bool = false,
        recordingStartTime: Date? = nil,
        catchupSessionId: String? = nil,
        catchupGuideReturnTime: Date? = nil
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
        currentlyPlayingCatchupSessionId = catchupSessionId
        self.catchupGuideReturnTime = catchupGuideReturnTime
        isPreparingStream = false
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
        currentlyPlayingCatchupSessionId = nil
    }

    /// Clears the pending target only after the reconstructed macOS guide has
    /// had time to install its scroll anchors and restore the horizontal
    /// position. The match prevents an old restoration task from clearing a
    /// newer playback target.
    func clearCatchupGuideReturnTime(ifMatching returnTime: Date) {
        guard catchupGuideReturnTime == returnTime else { return }
        catchupGuideReturnTime = nil
    }

    /// Dismiss the player UI without clearing playback state (used for PiP).
    func dismissPlayer() {
        isShowingPlayer = false
    }
}
