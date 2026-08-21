//
//  ChannelCatchupView.swift
//  NexusPVR
//
//  Archived programs available for one Dispatcharr catch-up channel.
//

import SwiftUI

#if DISPATCHERPVR
struct ChannelCatchupView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var epgCache: EPGCache

    let channel: Channel

    @State private var programs: [Program] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if programs.isEmpty {
                emptyView
            } else {
                ChannelCatchupResultsView(
                    channel: channel,
                    programs: programs
                )
            }
        }
        .navigationTitle("\(channel.name) Catch-up")
        .accessibilityIdentifier("channel-catchup-view")
        .background(Theme.background)
        .task {
            await loadPrograms()
        }
        #if os(tvOS)
        .onExitCommand {
            appState.selectedCatchupChannel = nil
        }
        #endif
    }

    private var loadingView: some View {
        VStack(spacing: Theme.spacingMD) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.catchup)
            Text("Loading catch-up programs...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Theme.catchup)
            Text("No Catch-up Programs")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("No archived programs are currently available for \(channel.name).")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tvOSFocusableEmptyState()
    }

    private func loadPrograms() async {
        isLoading = true

        let now = Date()
        if let oldestArchiveDate = Calendar.current.date(
            byAdding: .day,
            value: -channel.catchupDays,
            to: now
        ) {
            await epgCache.ensureDay(oldestArchiveDate, using: client)
        }

        guard !Task.isCancelled else { return }
        programs = CatchupAvailability.availablePrograms(
            from: epgCache.allPrograms(for: channel.id),
            channelIsCatchup: channel.isCatchup,
            catchupDays: channel.catchupDays,
            now: now
        )
        isLoading = false
    }

}
#endif
