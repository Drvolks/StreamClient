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

        // Ensure App Group has latest data for Top Shelf extension
        UserPreferences.load().save()
        ServerConfig.load().save()

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
                .tint(Theme.accent)
                #if !os(macOS)
                .ignoresSafeArea()
                #endif
                .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                    // Reload server config if it changed from iCloud.
                    // Skip if the user just unlinked — the iCloud removal
                    // notification can arrive after the clear() and re-apply
                    // a stale config from the sync queue.
                    guard client.isConfigured else { return }
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

    private func validateAuthenticationOnForeground() {
        guard client.isConfigured else { return }

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
            guard !Task.isCancelled, client.isConfigured, client.config == expectedConfig else { return }

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
                    let streamURL = try await client.recordingStreamURL(recordingId: id)
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
                        streamURL = try await client.liveStreamURL(channelId: id)
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
