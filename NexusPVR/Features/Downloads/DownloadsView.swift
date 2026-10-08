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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacDownloadsHeader(
                count: downloads.items.count,
                totalBytes: downloads.items.reduce(0) { $0 + (($1.state == .completed) ? ($1.byteSize ?? 0) : 0) },
                activeCount: downloads.items.filter(\.state.isActive).count
            )
            content
        }
        .background(MidnightGradients.ground(colorScheme))
        .modifier(DownloadsChrome(downloads: downloads))
        #else
        content
            .background(MidnightGradients.ground(colorScheme))
            .modifier(DownloadsChrome(downloads: downloads))
        #endif
    }

    private var content: some View {
        Group {
            if downloads.items.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        #if os(macOS)
        macList
        #else
        rowList
        #endif
    }

    /// In progress, then ready to watch, then failed (Midnight).
    private var sections: [(title: String, items: [DownloadItem])] {
        [
            ("In progress", downloads.items.filter(\.state.isActive)),
            ("Ready to watch", downloads.items.filter { $0.state == .completed }),
            ("Failed", downloads.items.filter { if case .failed = $0.state { return true } else { return false } })
        ].filter { !$0.items.isEmpty }
    }

    #if os(macOS)
    private var macList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections, id: \.title) { section in
                    MidnightSectionHeader(
                        title: section.title,
                        meta: "\(section.items.count) download\(section.items.count == 1 ? "" : "s")"
                    )
                    ForEach(section.items) { item in
                        MacDownloadRow(
                            item: item,
                            play: { play(item, fromStart: false) },
                            playFromStart: { play(item, fromStart: true) },
                            reveal: { reveal(item) },
                            retry: { Task { await downloads.retry(item, using: client) } },
                            remove: { Task { await downloads.delete(item) } }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, Theme.spacingLG)
        }
    }
    #endif

    private var rowList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections, id: \.title) { section in
                    MidnightSectionHeader(
                        title: section.title,
                        meta: "\(section.items.count) download\(section.items.count == 1 ? "" : "s")"
                    )
                    .padding(.horizontal, 16)
                    ForEach(section.items) { item in
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
            }
            .padding(.bottom, 120)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(MidnightPalette.accent)
            Text("No downloads")
                .midnightDisplay(20)
                .foregroundStyle(MidnightPalette.ink)
            Text(emptyMessage)
                .font(.archivo(12.5))
                .foregroundStyle(MidnightPalette.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.horizontal, Theme.spacingLG)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        #if os(macOS)
        "Download a catch-up program or a recording to keep it on this Mac and watch it offline."
        #else
        "Download a catch-up program or a recording to keep it on this device and watch it offline."
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

/// Title, identifier, refresh and the start-error alert, shared by both layouts.
private struct DownloadsChrome: ViewModifier {
    @ObservedObject var downloads: DownloadManager

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .midnightNavigationTitle(
                "Downloads",
                kicker: "Offline · \(downloads.items.count) download\(downloads.items.count == 1 ? "" : "s")"
            )
            #else
            .navigationTitle("Downloads")
            #endif
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
}
#endif
