//
//  AppEntry.swift
//  PVR Client
//
//  App entry point for iOS, iPadOS, tvOS, and macOS
//

import SwiftUI

@main
struct PVRApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var client = PVRClient()
    @StateObject private var epgCache = EPGCache()
    #if !os(tvOS)
    /// Offline downloads library — see `DownloadsView`. Not offered on tvOS,
    /// which has no meaningful local storage for it.
    @StateObject private var downloadManager = DownloadManager()
    #endif
    @State private var foregroundAuthTask: Task<Void, Never>?

    init() {
        // Check for --demo-mode launch argument (used by UI tests)
        if ProcessInfo.processInfo.arguments.contains("--demo-mode") {
            let demoConfig = ServerConfig(host: "demo", port: 8866, pin: "", useHTTPS: false)
            demoConfig.save()

            // Use in-memory preferences seeded with demo keywords
            var demoPrefs = UserPreferences()
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-topics") {
                demoPrefs.keywords = ["__no_topic_matches__"]
            } else {
                demoPrefs.keywords = DemoDataProvider.keywords
            }
            UserPreferences.demoStore = demoPrefs
        }

        // Trigger iCloud sync on startup to pull latest data
        NSUbiquitousKeyValueStore.default.synchronize()

        // Ensure App Group has latest data for Top Shelf extension.
        // Both loads mirror the resolved value to the App Group on their own;
        // neither may re-publish it as if it were a fresh edit. `synchronize()`
        // above doesn't block, so a launch can still read a stale local copy,
        // and stamping that as new would clobber a newer value from another
        // device — `load()` alone keeps `updatedAt` intact so the timestamp
        // resolution still picks the real winner, and `saveLocally()` skips the
        // iCloud write entirely (ServerConfig has no timestamp to resolve with).
        _ = UserPreferences.load()
        ServerConfig.load().saveLocally()

        #if os(tvOS)
        // Seed the global the scaled fonts/metrics read (#107). AppState's
        // `didSet` mirror only fires on later changes, so the launch value
        // has to be written here, before the first view body runs.
        Theme.uiFontSize = UserPreferences.load().uiFontSize
        #endif

        // Start observing iCloud preference sync
        UserPreferences.startObservingSync {
            // Post notification when preferences change from another device
            NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(client)
                .environmentObject(epgCache)
                #if !os(tvOS)
                .environmentObject(downloadManager)
                .task {
                    downloadManager.appState = appState
                    await downloadManager.refresh()
                }
                #endif
                .tint(Theme.accent)
                #if !os(macOS)
                .ignoresSafeArea()
                #endif
                // Appearance override (#108). `nil` follows the device setting.
                .preferredColorScheme(appState.theme.colorScheme)
                #if os(tvOS)
                // UI font size (#107). Covers every semantic font in the
                // app; explicit point sizes are scaled by Theme's tv*
                // fonts. Reading `appState` here also re-renders the tree
                // when the setting changes, so it applies live.
                .dynamicTypeSize(appState.uiFontSize.dynamicTypeSize)
                #endif
                #if os(macOS)
                .onAppear { applyAppearance(appState.theme) }
                .onChange(of: appState.theme) { _, newTheme in applyAppearance(newTheme) }
                #endif
                .onReceive(NotificationCenter.default.publisher(for: .preferencesDidSync)) { _ in
                    // Picks up a theme changed on another device via iCloud.
                    let prefs = UserPreferences.load()
                    if prefs.theme != appState.theme {
                        appState.theme = prefs.theme
                    }
                    #if os(tvOS)
                    // Same for the UI font size (#107) — both when it's
                    // changed here in Settings and when another Apple TV on
                    // the same Apple ID syncs a new value.
                    if prefs.uiFontSize != appState.uiFontSize {
                        appState.uiFontSize = prefs.uiFontSize
                    }
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                    // Reload server config if it changed from iCloud.
                    // Skip if the user just unlinked — the iCloud removal
                    // notification can arrive after the clear() and re-apply
                    // a stale config from the sync queue.
                    guard client.isConfigured else { return }
                    // Skip while the server setup sheet is open — an incoming
                    // config would overwrite the address being typed and reset
                    // the connect it started.
                    guard !ServerConfigSyncGate.isSuspended else { return }
                    let newConfig = ServerConfig.load()
                    if newConfig.isConfigured && newConfig != client.config {
                        client.updateConfig(newConfig)
                        epgCache.invalidate()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    validateAuthenticationOnForeground()
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        #endif
    }

    #if os(macOS)
    /// Applies the theme to the AppKit layer so the title bar, menus and
    /// popovers follow the override too (#108).
    private func applyAppearance(_ theme: AppTheme) {
        NSApplication.shared.appearance = theme.nsAppearance
    }
    #endif

    private func validateAuthenticationOnForeground() {
        // Skip while a live stream is open — re-auth rotates the SID that owns the
        // server-side handle, so the renewals stop reaching it and the stream is
        // torn down ~15s later. See ForegroundAuthPolicy (#133).
        guard ForegroundAuthPolicy.shouldReauthenticate(
            isConfigured: client.isConfigured,
            hasActiveLiveStream: client.hasActiveLiveStream
        ) else { return }

        let expectedConfig = client.config
        foregroundAuthTask?.cancel()
        foregroundAuthTask = Task {
            await authenticateConfiguredClientOnForeground(expectedConfig: expectedConfig)
            await MainActor.run {
                if client.config == expectedConfig {
                    foregroundAuthTask = nil
                }
            }
        }
    }

    private func authenticateConfiguredClientOnForeground(expectedConfig: ServerConfig) async {
        let retryDelays: [Double] = [0.75, 1.5, 3.0]

        for attempt in 1...retryDelays.count {
            guard !Task.isCancelled, client.config == expectedConfig,
                  ForegroundAuthPolicy.shouldReauthenticate(
                    isConfigured: client.isConfigured,
                    hasActiveLiveStream: client.hasActiveLiveStream
                  ) else { return }

            do {
                try await client.authenticate()
                return
            } catch {
                guard attempt < retryDelays.count else { return }
                try? await Task.sleep(for: .seconds(retryDelays[attempt - 1]))
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host,
              let idString = url.pathComponents.last,
              let id = Int(idString) else {
            return
        }

        switch host {
        case "recording":
            Task {
                do {
                    let streamURL = try await appState.preparingStream {
                        try await client.recordingStreamURL(recordingId: id)
                    }
                    appState.playStream(url: streamURL, title: "Recording", recordingId: id)
                } catch {
                    appState.showAlert("Failed to play recording: \(error.localizedDescription)")
                }
            }
        case "channel":
            Task {
                do {
                    let channels = try await client.getChannels()
                    let channel = channels.first(where: { $0.id == id })
                    let channelName = channel?.name ?? "Channel \(id)"
                    // Prefer direct stream URL from channel data (same as ProgramDetailView)
                    let streamURL: URL
                    if let directURL = channel?.streamURL, let url = URL(string: directURL) {
                        streamURL = url
                    } else {
                        streamURL = try await appState.preparingStream {
                            try await client.liveStreamURL(channelId: id)
                        }
                    }
                    appState.playStream(url: streamURL, title: channelName, channelId: id, channelName: channelName)
                } catch {
                    appState.showAlert("Failed to play channel: \(error.localizedDescription)")
                }
            }
        default:
            break
        }
    }
}
