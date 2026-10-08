//
//  MacDownloadRow.swift
//  nextpvr-apple-client
//
//  A download in the macOS library (Midnight), in the recordings row style:
//  title, channel and air date, progress or status; on the right its watch
//  state, length and size, then an action strip.
//

#if os(macOS)
import SwiftUI

struct MacDownloadRow: View {
    let item: DownloadItem
    let play: () -> Void
    let playFromStart: () -> Void
    let reveal: () -> Void
    let retry: () -> Void
    let remove: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isCompleted: Bool { item.state == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            details
            Spacer(minLength: Theme.spacingSM)
            facts
            actionStrip
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(isHovering ? MidnightPalette.hoverTint : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            if isCompleted { play() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("download-row")
    }

    // MARK: Left

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.archivo(15.5, .extraBold))
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(2)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.archivo(12.5))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
            }
            if let context = contextLine {
                Text(context)
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
            }
            status
        }
    }

    @ViewBuilder
    private var status: some View {
        switch item.state {
        case .queued:
            Text("Waiting…")
                .midnightMeta(11)
                .foregroundStyle(MidnightPalette.inkFaint)
        case .running(let seconds, let bytes):
            VStack(alignment: .leading, spacing: 4) {
                progressBar(DownloadPolicy.progress(writtenSeconds: seconds, expectedDuration: item.expectedDuration))
                Text("\(Self.duration(seconds)) downloaded · \(Self.size(bytes))")
                    .midnightMeta(10.5)
                    .foregroundStyle(MidnightPalette.inkSoft)
            }
            .padding(.top, 2)
        case .completed:
            if let resume = resumeProgress {
                progressBar(resume)
                    .padding(.top, 2)
                    .accessibilityLabel("\(Int(resume * 100)) percent watched")
            }
        case .failed(let message):
            Text(message)
                .font(.archivo(12))
                .foregroundStyle(MidnightPalette.danger)
                .lineLimit(3)
                .frame(maxWidth: 520, alignment: .leading)
        }
    }

    /// A determinate bar when `fraction` is known, a running one otherwise.
    @ViewBuilder
    private func progressBar(_ fraction: Double?) -> some View {
        if let fraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(MidnightPalette.barSoft)
                    Rectangle()
                        .fill(MidnightGradients.field(colorScheme))
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(width: 260, height: 3)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var contextLine: String? {
        var parts: [String] = []
        if let channelName = item.channelName { parts.append(channelName) }
        if let start = item.programStart {
            parts.append(start.formatted(.dateTime.month(.abbreviated).day()))
            parts.append(GuideCellTimeLabel.time(start))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Right

    private var facts: some View {
        VStack(alignment: .trailing, spacing: 6) {
            stateChip
            if let seconds = item.writtenSeconds, isCompleted {
                Text(Self.duration(seconds))
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
            }
            if let bytes = item.byteSize, isCompleted {
                Text(Self.size(bytes))
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
            }
            if isCompleted && item.fileExtension != "mp4" {
                Text(item.fileExtension.uppercased())
                    .midnightMeta(10.5)
                    .foregroundStyle(MidnightPalette.inkFaint)
            }
        }
        .frame(width: 104, alignment: .trailing)
    }

    @ViewBuilder
    private var stateChip: some View {
        switch item.state {
        case .queued, .running:
            MidnightFieldChip(text: "Downloading", size: 9)
        case .completed:
            MacWatchStateChip(state: watchState)
        case .failed:
            Text("Failed")
                .badgeLabel()
                .foregroundStyle(MidnightPalette.danger)
                .overlay { Rectangle().strokeBorder(MidnightPalette.danger, lineWidth: 1) }
        }
    }

    /// Same three states as a recording, read from the download's own
    /// playback position.
    private var watchState: RecordingWatchState {
        if let progress = resumeProgress { return .resume(progress: progress) }
        if (item.playbackPosition ?? 0) > DownloadItem.minimumResumeSeconds { return .watched }
        return .new
    }

    private var resumeProgress: Double? {
        guard let resume = item.resumeSeconds, let total = item.writtenSeconds, total > 0 else { return nil }
        return min(max(Double(resume) / total, 0), 1)
    }

    private var actionStrip: some View {
        HStack(spacing: 0) {
            switch item.state {
            case .completed:
                MidnightActionCell(systemImage: "gobackward", help: "Start over", action: playFromStart)
                divider
                MidnightActionCell(systemImage: "play.fill", help: item.hasResumePosition ? "Resume" : "Play", action: play)
                    .accessibilityIdentifier("download-play-button")
                divider
                MidnightActionCell(systemImage: "folder", help: "Show in Finder", action: reveal)
                divider
            case .failed:
                MidnightActionCell(systemImage: "arrow.clockwise", help: "Retry", action: retry)
                    .accessibilityIdentifier("download-retry-button")
                divider
            case .queued, .running:
                EmptyView()
            }
            MidnightActionCell(
                systemImage: item.state.isActive ? "xmark" : "trash",
                help: item.state.isActive ? "Cancel download" : "Delete download",
                hoverFill: MidnightPalette.danger,
                action: remove
            )
            .accessibilityIdentifier("download-remove-button")
        }
        .frame(width: CGFloat(cellCount) * 34 + CGFloat(cellCount - 1), height: 34)
        .overlay { Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
    }

    private var cellCount: Int {
        switch item.state {
        case .completed: 4
        case .failed: 2
        case .queued, .running: 1
        }
    }

    private var divider: some View {
        Rectangle().fill(MidnightPalette.lineSoft).frame(width: 1)
    }

    // MARK: Formatting

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
