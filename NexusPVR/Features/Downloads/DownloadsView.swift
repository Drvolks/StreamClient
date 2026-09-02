//
//  DownloadsView.swift
//  NexusPVR
//
//  The offline downloads library.
//

import SwiftUI

#if !os(tvOS)
struct DownloadsView: View {
    @EnvironmentObject private var client: PVRClient
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        Group {
            if downloads.items.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Downloads")
        .accessibilityIdentifier("downloads-view")
        .task { await downloads.refresh() }
        .alert(
            "Download",
            isPresented: Binding(
                get: { downloads.startError != nil },
                set: { if !$0 { downloads.startError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { downloads.startError = nil }
        } message: {
            Text(downloads.startError ?? "")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spacingSM) {
                ForEach(downloads.items) { item in
                    DownloadRow(
                        item: item,
                        fileURL: downloads.fileURL(for: item),
                        play: { play(item, fromStart: false) },
                        playFromStart: { play(item, fromStart: true) },
                        reveal: { reveal(item) },
                        retry: { Task { await downloads.retry(item, using: client) } },
                        remove: { Task { await downloads.delete(item) } }
                    )
                }
            }
            .padding(Theme.spacingMD)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("No Downloads")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        #if os(macOS)
        "Download a catch-up programme or a recording to keep it on this Mac and watch it offline."
        #else
        "Download a catch-up programme or a recording to keep it on this device and watch it offline."
        #endif
    }

    private func play(_ item: DownloadItem, fromStart: Bool) {
        guard let url = downloads.fileURL(for: item) else { return }
        if fromStart {
            Task { await downloads.clearPlaybackPosition(for: item) }
        }
        appState.playStream(
            url: url,
            title: item.displayTitle,
            downloadId: item.id,
            resumePosition: fromStart ? nil : item.resumeSeconds
        )
    }

    /// macOS only: iOS has no file viewer to reveal into, and gets a share
    /// sheet in the row instead.
    private func reveal(_ item: DownloadItem) {
        #if os(macOS)
        guard let url = downloads.fileURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
#endif
