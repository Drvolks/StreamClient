//
//  DownloadRow.swift
//  NexusPVR
//
//  One row of the offline downloads library.
//

import SwiftUI

#if !os(tvOS)
struct DownloadRow: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let item: DownloadItem
    /// Where the media file sits, for the share sheet. `nil` until the library
    /// has been read from disk.
    let fileURL: URL?
    let play: () -> Void
    let playFromStart: () -> Void
    let reveal: () -> Void
    let retry: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    // Two lines, wrapping: a programme title is the one thing
                    // in the row worth reading in full, and truncating it to
                    // one line loses the episode or event that distinguishes
                    // two recordings of the same show.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Text(contextLine)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    // Secondary detail: better clipped than wrapped onto a
                    // second line that pushes the status out of view.
                    .lineLimit(1)

                statusView
            }
            // Claims every point the buttons don't need. Without this the text
            // column and a `Spacer` are both flexible, so the layout splits the
            // leftover width between them — truncating the title while empty
            // space sits next to it.
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
                .layoutPriority(1)
        }
        .padding(Theme.spacingMD)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMD))
        .accessibilityIdentifier("download-row")
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        switch item.state {
        case .queued:
            Label("Waiting…", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

        case .running(let seconds, let bytes):
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                if let progress = DownloadPolicy.progress(writtenSeconds: seconds, expectedDuration: item.expectedDuration) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 320)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(Self.duration(seconds)) downloaded · \(Self.size(bytes))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, Theme.spacingXS)

        case .completed:
            Label(completedSummary, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.success)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.error)
                .lineLimit(3)
        }
    }

    private var completedSummary: String {
        var parts: [String] = []
        if let seconds = item.writtenSeconds { parts.append(Self.duration(seconds)) }
        if let bytes = item.byteSize { parts.append(Self.size(bytes)) }
        if item.fileExtension != "mp4" { parts.append(item.fileExtension.uppercased()) }
        if let resume = item.resumeSeconds {
            parts.append("\(Self.duration(Double(resume))) watched")
        }
        return parts.isEmpty ? "Ready to watch" : parts.joined(separator: " · ")
    }

    private var contextLine: String {
        var parts: [String] = []
        if let channelName = item.channelName { parts.append(channelName) }
        if let start = item.programStart { parts.append(Self.broadcastDate(start)) }
        return parts.joined(separator: " · ")
    }

    /// Day, month and time — with the year only when it isn't this one. The
    /// full `.abbreviated` style spends a quarter of a phone-width row on
    /// "2026", which pushes the channel name out of view.
    private static func broadcastDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        let style = Date.FormatStyle()
            .month(.abbreviated)
            .day()
            .hour()
            .minute()
        return date.formatted(sameYear ? style : style.year())
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        // On a phone the labelled buttons take a third of the row — width the
        // title and channel need more than the words do.
        if isCompact {
            actionButtons.labelStyle(.iconOnly)
        } else {
            actionButtons
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Theme.spacingSM) {
            switch item.state {
            case .completed:
                Button(action: play) {
                    Label(item.hasResumePosition ? "Resume" : "Play", systemImage: "play.fill")
                }
                .accessibilityIdentifier("download-play-button")

                if item.hasResumePosition {
                    Button(action: playFromStart) {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                    }
                    .labelStyle(.iconOnly)
                    .help("Start Over")
                    .accessibilityIdentifier("download-restart-button")
                }

                #if os(macOS)
                Button(action: reveal) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help("Show in Finder")
                #else
                // iOS has no Finder to reveal into; sharing is how a file
                // leaves the app — "Save to Files" included.
                if let fileURL, item.state == .completed {
                    ShareLink(item: fileURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly)
                }
                #endif

            case .failed:
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("download-retry-button")

            case .queued, .running:
                EmptyView()
            }

            Button(role: .destructive, action: remove) {
                Label(item.state.isActive ? "Cancel" : "Delete", systemImage: item.state.isActive ? "xmark" : "trash")
            }
            .labelStyle(.iconOnly)
            .help(item.state.isActive ? "Cancel download" : "Delete download")
            .accessibilityIdentifier("download-remove-button")
        }
        .buttonStyle(.bordered)
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    // MARK: - Formatting

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
#endif
