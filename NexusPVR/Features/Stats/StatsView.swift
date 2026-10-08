//
//  StatsView.swift
//  DispatcherPVR
//
//  Displays active proxy stream status from Dispatcharr
//

#if DISPATCHERPVR
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var client: PVRClient
    #if os(tvOS)
    @Environment(\.requestSidebarFocus) private var requestSidebarFocus
    @FocusState private var isRootFocused: Bool
    #endif
    @StateObject private var vm = StatsViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #elseif os(macOS)
        midnightBody
        #else
        midnightBody
            .midnightNavigationTitle(
                "Status",
                kicker: "\(vm.activeCount) active · \(vm.m3uAccounts.count) account\(vm.m3uAccounts.count == 1 ? "" : "s")"
            )
        #endif
    }

    // MARK: - macOS and iOS (Midnight)

    #if !os(tvOS)
    private var midnightBody: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            MacStatusHeader(activeCount: vm.activeCount, accountCount: vm.m3uAccounts.count)
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let message = vm.switchError {
                        MacSettingsHint(text: message)
                            .padding(.top, 14)
                    }

                    MidnightSectionHeader(
                        title: "Active streams",
                        meta: "\(vm.activeCount) channel\(vm.activeCount == 1 ? "" : "s")"
                    )
                    Group {
                        if vm.isLoading && vm.channels.isEmpty && vm.m3uAccounts.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else if let error = vm.error, vm.channels.isEmpty {
                            macNote(error, isError: true)
                        } else if vm.channels.isEmpty {
                            macNote("Channels appear here while they are being streamed.", isError: false)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(vm.channels) { channel in
                                    macCard(for: channel)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)

                    if !vm.m3uAccounts.isEmpty {
                        MidnightSectionHeader(
                            title: "M3U accounts",
                            meta: "\(vm.m3uAccounts.count) account\(vm.m3uAccounts.count == 1 ? "" : "s")"
                        )
                        .padding(.top, 10)
                        ForEach(vm.m3uAccounts) { account in
                            MacM3UAccountRow(account: account)
                        }
                    }
                }
                #if os(macOS)
                .padding(.horizontal, 20)
                .padding(.bottom, Theme.spacingLG)
                #else
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
                #endif
            }
        }
        .background(MidnightGradients.ground(colorScheme))
        .task {
            vm.startRefreshing(client: client, appState: appState)
        }
        .onDisappear {
            vm.stopRefreshing()
        }
    }

    private func macCard(for channel: ProxyChannelStatus) -> some View {
        let canSwitch = vm.canSwitchStreams(client: client, appState: appState)
        return MacStreamCard(
            channel: channel,
            profileName: channel.profileLabel(nameLookup: { vm.profileName(forId: $0) }),
            streams: canSwitch ? vm.streams(for: channel) : [],
            activeStreamId: vm.activeStreamId(for: channel),
            isSwitchingStream: vm.isSwitching(channel),
            accountNameLookup: { vm.m3uAccountName(forId: $0) },
            onSelectStream: canSwitch ? { stream in
                Task { await vm.switchStream(channel: channel, to: stream, client: client, appState: appState) }
            } : nil
        )
        .task(id: channel.id) {
            guard canSwitch else { return }
            await vm.loadStreams(for: channel, client: client)
        }
    }

    private func macNote(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.archivo(12.5))
            .foregroundStyle(isError ? MidnightPalette.danger : MidnightPalette.inkSoft)
            .padding(.vertical, 8)
    }
    #endif

    // MARK: - tvOS

    #if os(tvOS)
    private var tvOSBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                header
                    .padding(.horizontal, 80)

                switchErrorBanner
                    .padding(.horizontal, 80)

                if vm.isLoading && vm.channels.isEmpty && vm.m3uAccounts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = vm.error, vm.channels.isEmpty {
                    errorView(error)
                        .padding(.horizontal, 80)
                } else if vm.channels.isEmpty {
                    emptyView
                        .padding(.horizontal, 80)
                } else {
                    LazyVStack(spacing: Theme.spacingLG) {
                        ForEach(vm.channels) { channel in
                            card(for: channel)
                        }
                    }
                    .padding(.horizontal, 80)
                }

                // M3U Accounts section
                if !vm.m3uAccounts.isEmpty {
                    m3uAccountsSection
                        .padding(.horizontal, 80)
                }
            }
            .padding(.vertical, 40)
        }
        .focusable(true)
        .focused($isRootFocused)
        .focusEffectDisabled()
        .background(.ultraThinMaterial)
        .onAppear {
            DispatchQueue.main.async {
                isRootFocused = true
            }
        }
        .onExitCommand {
            requestSidebarFocus()
        }
        .onMoveCommand { direction in
            if direction == .left { requestSidebarFocus() }
        }
        .task {
            vm.startRefreshing(client: client, appState: appState)
        }
        .onDisappear {
            vm.stopRefreshing()
        }
    }
    #endif

    // MARK: - Shared Components

    /// Builds a channel card, wiring the stream switcher when the user is
    /// allowed to change sources (#116).
    private func card(for channel: ProxyChannelStatus) -> some View {
        let canSwitch = vm.canSwitchStreams(client: client, appState: appState)
        return ChannelStatusCard(
            channel: channel,
            profileNameLookup: { vm.profileName(forId: $0) },
            streams: canSwitch ? vm.streams(for: channel) : [],
            activeStreamId: vm.activeStreamId(for: channel),
            isSwitchingStream: vm.isSwitching(channel),
            accountNameLookup: { vm.m3uAccountName(forId: $0) },
            onSelectStream: canSwitch ? { stream in
                Task { await vm.switchStream(channel: channel, to: stream, client: client, appState: appState) }
            } : nil
        )
        .task(id: channel.id) {
            guard canSwitch else { return }
            await vm.loadStreams(for: channel, client: client)
        }
    }

    @ViewBuilder
    private var switchErrorBanner: some View {
        if let message = vm.switchError {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Streams")
                    .font(.displayMedium)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(vm.activeCount) active channel\(vm.activeCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !vm.channels.isEmpty {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var m3uAccountsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("M3U Accounts")
                .font(.displayMedium)
                .foregroundStyle(Theme.textPrimary)

            ForEach(vm.m3uAccounts) { account in
                M3UAccountRow(account: account)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("No Active Streams")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Channels will appear here when they are being streamed")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .tvOSFocusableEmptyState()
    }
}

// MARK: - M3U Account Row

struct M3UAccountRow: View {
    let account: M3UAccount

    private var statusColor: Color {
        switch account.status {
        case "success": return Theme.success
        case "error": return Theme.error
        default: return Theme.warning
        }
    }

    private var accountTypeBadge: String {
        switch account.accountType?.lowercased() {
        case "xtream_codes": return "XC"
        default: return "STD"
        }
    }

    private var formattedDate: String? {
        guard let dateString = account.updatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        guard let date = formatter.date(from: dateString) ?? fallback.date(from: dateString) else { return nil }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(accountTypeBadge)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.surfaceHighlight)
                        .clipShape(Capsule())
                }
                Text(account.serverUrl)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                StateBadge(state: account.status)
                if let date = formattedDate {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
    }
}

// MARK: - Channel Status Card

struct ChannelStatusCard: View {
    let channel: ProxyChannelStatus
    var profileNameLookup: ((Int) -> String?)? = nil
    /// Streams the channel can play. Empty hides the switcher (#116).
    var streams: [ChannelStream] = []
    var activeStreamId: Int? = nil
    var isSwitchingStream = false
    var accountNameLookup: ((Int) -> String?)? = nil
    var onSelectStream: ((ChannelStream) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            // Header: name [profile] + state badge
            HStack {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                StateBadge(state: channel.state)
            }

            // Stats grid
            #if os(tvOS)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.spacingSM) {
                statsRows
            }
            #else
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.spacingSM) {
                statsRows
            }
            #endif

            // Stream switcher
            if let onSelectStream, !streams.isEmpty {
                StreamSelectorView(
                    streams: streams,
                    activeStreamId: activeStreamId,
                    isSwitching: isSwitchingStream,
                    accountNameLookup: accountNameLookup,
                    onSelect: onSelectStream
                )
            }

            // Connected clients
            if let clients = channel.clients, !clients.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Text("Connected Clients (\(channel.clientCount ?? clients.count))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(clients) { client in
                        ClientRow(client: client)
                    }
                }
            }
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
    }

    @ViewBuilder
    private var statsRows: some View {
        if let resolution = channel.resolution {
            StatRow(label: "Resolution", value: resolution)
        }
        StatRow(label: "Codecs", value: channel.codecSummary)
        if let bitrate = channel.avgBitrate {
            StatRow(label: "Bitrate", value: bitrate)
        }
        if let fps = channel.sourceFps {
            StatRow(label: "FPS", value: String(format: "%.0f", fps))
        }
        if let speed = channel.ffmpegSpeed {
            StatRow(label: "FFmpeg Speed", value: String(format: "%.2fx", speed))
        }
        if let uptime = channel.uptime {
            StatRow(label: "Uptime", value: ProxyChannelStatus.durationText(uptime))
        }
        if let bytes = channel.totalBytes {
            StatRow(label: "Total Data", value: ProxyChannelStatus.dataText(bytes))
        }
    }

    private var displayName: String {
        let name = channel.displayName
        guard let profile = channel.profileLabel(nameLookup: profileNameLookup) else { return name }
        return "\(name) [\(profile)]"
    }
}

// MARK: - Supporting Views

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

struct StateBadge: View {
    let state: String

    private var color: Color {
        switch state {
        case "streaming", "success", "active": return Theme.success
        case "error": return Theme.error
        default: return Theme.warning
        }
    }

    var body: some View {
        Text(state.replacingOccurrences(of: "_", with: " "))
            .font(.caption)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct ClientRow: View {
    let client: ProxyClientInfo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.ipAddress)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                Text(client.userAgent)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let since = client.connectedTime {
                Text(ProxyChannelStatus.durationText(since))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
