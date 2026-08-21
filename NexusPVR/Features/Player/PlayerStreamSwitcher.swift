//
//  PlayerStreamSwitcher.swift
//  DispatcherPVR
//
//  Stream selection for the channel playing in the player (#117)
//
//  Only the Dispatcharr build shows this (PlayerView gates on DISPATCHERPVR),
//  but the type stays ungated — like DispatcherClient and ChannelStream — so
//  the unit test target can exercise it.
//

import Foundation
import Combine

/// Backs the stream picker in the player's video information panel.
///
/// The stats page has the same picker per active channel (#116); here only the
/// channel being watched matters, so the state is a single channel's worth.
@MainActor
final class PlayerStreamSwitcher: ObservableObject {
    /// Streams assigned to the playing channel, in the channel's configured order.
    @Published private(set) var streams: [ChannelStream] = []
    /// Stream the proxy reports the channel is playing.
    @Published private(set) var reportedStreamId: Int?
    @Published private(set) var isSwitching = false
    @Published private(set) var errorMessage: String?

    private(set) var channelUUID: String?
    private var accountNames: [Int: String] = [:]
    private var loadedChannelId: Int?

    /// Locally selected stream id, kept until the server reports the switch.
    /// The proxy needs a few seconds to restart the source, so without this the
    /// picker would snap back to the previous stream right after a selection.
    private var pendingSelection: Int?
    private var pendingSelectionAt: Date?
    /// How long a local selection wins over the server's reported stream before
    /// it's dropped, so a failed switch can't pin the picker to the wrong stream.
    private let pendingSelectionTimeout: TimeInterval = 20
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// The stream to show as selected — the pending local selection while a
    /// switch is settling, otherwise whatever the server reports.
    var activeStreamId: Int? { pendingSelection ?? reportedStreamId }

    /// Switching is an admin action on the Dispatcharr REST/proxy API, so the
    /// picker is hidden for read-only and output-only (Streamer) users.
    static func canSwitchStreams(client: DispatcherClient, appState: AppState) -> Bool {
        appState.userLevel >= 10 && !client.useOutputEndpoints && !client.config.isDemoMode
    }

    func label(for stream: ChannelStream) -> String {
        stream.label(accountNameLookup: { [accountNames] id in accountNames[id] })
    }

    // MARK: - Loading

    /// Loads the streams assigned to the playing channel. Reloads only when the
    /// channel changes, so the player's status polling can call it freely.
    func load(channelId: Int?, client: DispatcherClient) async {
        guard let channelId else {
            reset()
            return
        }
        guard loadedChannelId != channelId else { return }

        reset()
        loadedChannelId = channelId
        channelUUID = client.channelUUID(forId: channelId)

        do {
            let loaded = try await client.getChannelStreams(channelId: channelId)
            // A channel switch mid-load would make this stale.
            guard loadedChannelId == channelId else { return }
            streams = loaded
        } catch {
            // Allow a retry on the next channel change / panel open.
            loadedChannelId = nil
            return
        }

        if let accounts = try? await client.getM3UAccounts(), loadedChannelId == channelId {
            accountNames = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Picks the playing channel out of a `/proxy/ts/status` response and takes
    /// the stream it reports. Channels missing from the response (they drop out
    /// briefly while a switch restarts the source) leave the state untouched.
    func applyStatus(_ channels: [ProxyChannelStatus]) {
        guard let channelUUID else { return }
        guard let match = channels.first(where: { $0.channelId == channelUUID }) else { return }
        reportedStreamId = match.streamId
        clearPendingSelectionIfSettled(reported: match.streamId)
    }

    func reset() {
        streams = []
        reportedStreamId = nil
        errorMessage = nil
        channelUUID = nil
        accountNames = [:]
        loadedChannelId = nil
        pendingSelection = nil
        pendingSelectionAt = nil
    }

    // MARK: - Switching

    func select(_ stream: ChannelStream, client: DispatcherClient) async {
        guard let channelUUID, !isSwitching else { return }

        errorMessage = nil
        isSwitching = true
        defer { isSwitching = false }

        do {
            try await client.switchStream(channelUUID: channelUUID, streamId: stream.id)
            pendingSelection = stream.id
            pendingSelectionAt = now()
        } catch {
            errorMessage = "Could not switch to \(stream.displayName): \(error.localizedDescription)"
        }
    }

    private func clearPendingSelectionIfSettled(reported: Int?) {
        guard let pending = pendingSelection else { return }
        let expired = now().timeIntervalSince(pendingSelectionAt ?? now()) > pendingSelectionTimeout
        if reported == pending || expired {
            pendingSelection = nil
            pendingSelectionAt = nil
        }
    }

    #if DEBUG
    /// Test seam: puts the switcher in the state `load(channelId:client:)` would.
    func prepareForTesting(channelUUID: String, streams: [ChannelStream], accountNames: [Int: String] = [:]) {
        self.channelUUID = channelUUID
        self.streams = streams
        self.accountNames = accountNames
    }

    /// Test seam: records a selection as if the switch request had succeeded.
    func markPendingSelectionForTesting(_ streamId: Int, at date: Date) {
        pendingSelection = streamId
        pendingSelectionAt = date
    }
    #endif
}
