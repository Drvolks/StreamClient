//
//  StatsViewModel.swift
//  DispatcherPVR
//
//  View model for proxy stream status monitoring
//

#if DISPATCHERPVR
import Foundation
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var channels: [ProxyChannelStatus] = []
    @Published var m3uAccounts: [M3UAccount] = []
    @Published var activeCount = 0
    @Published var isLoading = false
    @Published var error: String?
    /// Selectable streams per active channel, keyed by the proxy channel UUID.
    @Published var streamsByChannel: [String: [ChannelStream]] = [:]
    /// Channels with a stream switch in flight, keyed by the proxy channel UUID.
    @Published var switchingChannels: Set<String> = []
    @Published var switchError: String?

    /// Locally selected stream ids, kept until the server reports the switch.
    /// The proxy needs a few seconds to restart the source, so without this the
    /// picker would snap back to the previous stream right after a selection.
    private var pendingSelections: [String: Int] = [:]
    private var pendingSelectionTimes: [String: Date] = [:]
    /// How long a local selection wins over the server's reported stream before
    /// it's dropped, so a failed switch can't pin the picker to the wrong stream.
    private let pendingSelectionTimeout: TimeInterval = 20
    private var streamLoads: Set<String> = []
    private var refreshTask: Task<Void, Never>?

    func startRefreshing(client: DispatcherClient, appState: AppState) {
        stopRefreshing()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(client: client, appState: appState)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func profileName(forId id: Int) -> String? {
        for account in m3uAccounts {
            if let match = account.profiles.first(where: { $0.id == id }) {
                return match.name
            }
        }
        return nil
    }

    // MARK: - Stream Switching

    /// Switching a stream is an admin action on the Dispatcharr REST/proxy API,
    /// so it's hidden for read-only and output-only (Streamer) users.
    func canSwitchStreams(client: DispatcherClient, appState: AppState) -> Bool {
        appState.userLevel >= 10 && !client.useOutputEndpoints && !client.config.isDemoMode
    }

    func streams(for channel: ProxyChannelStatus) -> [ChannelStream] {
        guard let uuid = channel.channelId else { return [] }
        return streamsByChannel[uuid] ?? []
    }

    /// The stream the channel is playing — the pending local selection while a
    /// switch is settling, otherwise whatever the server reports.
    func activeStreamId(for channel: ProxyChannelStatus) -> Int? {
        guard let uuid = channel.channelId else { return channel.streamId }
        return pendingSelections[uuid] ?? channel.streamId
    }

    func isSwitching(_ channel: ProxyChannelStatus) -> Bool {
        guard let uuid = channel.channelId else { return false }
        return switchingChannels.contains(uuid)
    }

    func m3uAccountName(forId id: Int) -> String? {
        m3uAccounts.first(where: { $0.id == id })?.name
    }

    /// Loads the streams assigned to a channel once per active channel.
    func loadStreams(for channel: ProxyChannelStatus, client: DispatcherClient) async {
        guard let uuid = channel.channelId, !uuid.isEmpty else { return }
        guard !streamLoads.contains(uuid) else { return }
        streamLoads.insert(uuid)

        guard let channelId = await client.channelId(forUUID: uuid) else {
            // Unresolvable channel (e.g. removed on the server) — allow a retry later.
            streamLoads.remove(uuid)
            return
        }

        do {
            let streams = try await client.getChannelStreams(channelId: channelId)
            streamsByChannel[uuid] = streams
        } catch {
            streamLoads.remove(uuid)
        }
    }

    func switchStream(channel: ProxyChannelStatus, to stream: ChannelStream, client: DispatcherClient, appState: AppState) async {
        guard let uuid = channel.channelId, !uuid.isEmpty else { return }
        guard !switchingChannels.contains(uuid) else { return }

        switchError = nil
        switchingChannels.insert(uuid)
        defer { switchingChannels.remove(uuid) }

        do {
            try await client.switchStream(channelUUID: uuid, streamId: stream.id)
            pendingSelections[uuid] = stream.id
            pendingSelectionTimes[uuid] = Date()
            await refresh(client: client, appState: appState)
        } catch {
            switchError = "Could not switch to \(stream.displayName): \(error.localizedDescription)"
        }
    }

    /// Drops per-channel caches for channels that stopped streaming, and clears
    /// pending selections once the server confirms (or overrides) them.
    private func reconcileStreamState() {
        // Channels mid-switch briefly drop out of the proxy status while the
        // source restarts, so keep their state until the switch settles.
        let activeUUIDs = Set(channels.compactMap(\.channelId)).union(switchingChannels)
        streamsByChannel = streamsByChannel.filter { activeUUIDs.contains($0.key) }
        streamLoads = streamLoads.intersection(activeUUIDs)

        let now = Date()
        for channel in channels {
            guard let uuid = channel.channelId, let pending = pendingSelections[uuid] else { continue }
            let expired = now.timeIntervalSince(pendingSelectionTimes[uuid] ?? now) > pendingSelectionTimeout
            if channel.streamId == pending || expired {
                pendingSelections[uuid] = nil
                pendingSelectionTimes[uuid] = nil
            }
        }
        pendingSelections = pendingSelections.filter { activeUUIDs.contains($0.key) }
        pendingSelectionTimes = pendingSelectionTimes.filter { pendingSelections[$0.key] != nil }
    }

    func refresh(client: DispatcherClient, appState: AppState) async {
        if channels.isEmpty && m3uAccounts.isEmpty {
            isLoading = true
        }
        error = nil

        do {
            let status = try await client.getProxyStatus()
            channels = status.channels ?? []
            activeCount = status.count ?? channels.count
            appState.activeStreamCount = activeCount
            reconcileStreamState()
        } catch {
            self.error = error.localizedDescription
        }

        do {
            let accounts = try await client.getM3UAccounts()
            m3uAccounts = accounts.filter { $0.isActive && !$0.locked }
            appState.hasM3UErrors = m3uAccounts.contains { $0.status != "success" }
        } catch {
            // Non-critical — M3U status is informational only
        }

        isLoading = false
    }
}
#endif
