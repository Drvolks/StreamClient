//
//  RecordingRow.swift
//  nextpvr-apple-client
//
//  Recording list row
//

import SwiftUI

/// "1h 30m", "45m", "20s": a stream duration in duration warnings.
func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 && minutes > 0 {
        return "\(hours)h \(minutes)m"
    } else if hours > 0 {
        return "\(hours)h"
    } else if minutes > 0 {
        return "\(minutes)m"
    } else {
        return "\(seconds)s"
    }
}

/// Determines if the file size suggests a complete recording (timestamp issue)
/// or a truncated file, and returns the appropriate warning label.
@ViewBuilder
private func durationWarningLabel(recording: Recording, mismatch: (expected: Int, detected: Int)) -> some View {
    // Check if file size is reasonable for the expected duration
    // 0.2 MB/s (1.6 Mbps) is a very conservative minimum for any video
    let fileSeemsComplete: Bool = {
        guard let size = recording.size, mismatch.expected > 0 else { return false }
        let bytesPerSecond = Double(size) / Double(mismatch.expected)
        return bytesPerSecond >= 200_000
    }()

    if fileSeemsComplete {
        Label {
            Text("Detected stream duration \(formatDuration(mismatch.detected)), playback may be impacted")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(Theme.warning)
    } else {
        Label {
            Text("Duration mismatch: expected \(formatDuration(mismatch.expected)), detected \(formatDuration(mismatch.detected))")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(Theme.warning)
    }
}

@ViewBuilder
private func durationUnverifiableLabel() -> some View {
    Label {
        Text("Duration could not be verified for this stream, playback may be impacted")
    } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
    }
    .font(.caption)
    .foregroundStyle(Theme.warning)
}

struct RecordingRow: View {
    let recording: Recording
    var showSeriesMeta: Bool = false
    var showSeriesDescriptionOneLine: Bool = false
    var hideSeriesChannelName: Bool = false
    var durationMismatch: (expected: Int, detected: Int)?
    var durationVerified: Bool = false
    var durationUnverifiable: Bool = false
    
    private var usesUnifiedMetadataLayout: Bool {
        recording.recordingStatus.isScheduled || recording.recordingStatus.isCompleted
    }

    private var cleanedEpisodeTitle: String? {
        guard let subtitle = recording.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subtitle.isEmpty else { return nil }
        let cleaned = SeriesInfo.stripPattern(from: subtitle).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private var primaryTitleText: String {
        if let episode = cleanedEpisodeTitle {
            return "\(recording.cleanName) - \(episode)"
        }
        return recording.cleanName
    }

    private var broadcastDateTimeText: String? {
        guard let start = recording.startDate else { return nil }
        if let end = recording.endDate {
            return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return start.formatted(date: .abbreviated, time: .shortened)
    }

    private var oneLineDescriptionText: String? {
        guard let desc = recording.desc?.trimmingCharacters(in: .whitespacesAndNewlines),
              !desc.isEmpty else { return nil }
        return desc
    }

    private func recordingProgress(at date: Date) -> Double? {
        guard recording.recordingStatus == .recording,
              let recordingStart = recording.recordingStartTime,
              let totalDuration = recording.totalRecordingDuration,
              totalDuration > 0 else { return nil }
        let elapsed = date.timeIntervalSince1970 - Double(recordingStart)
        return min(max(elapsed / Double(totalDuration), 0), 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacingMD) {
            // Left column: Status indicator (centered vertically)
            statusIcon

            // Content area
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                if usesUnifiedMetadataLayout {
                    // Row 1: SxxExx Program - Episode
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if showSeriesMeta, let series = recording.seriesInfo {
                            Text(series.shortDisplayString)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }

                        Text(primaryTitleText)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if recording.isLiveBroadcast { LiveBadge() }
                        if recording.isNew { NewBadge() }
                    }

                    // Row 2: Date/time | Duration (right unchanged)
                    HStack {
                        if let dateTime = broadcastDateTimeText {
                            Text(dateTime)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let duration = recording.durationMinutes {
                            Text("\(duration) min")
                                .font(.caption)
                                .foregroundStyle(durationVerified ? Theme.success : Theme.textTertiary)
                        }
                    }

                    // Row 3: Description one-liner | Size (right unchanged)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                        if let desc = oneLineDescriptionText {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let size = recording.fileSizeFormatted {
                            Text(size)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    // Row 1: Program title
                    HStack(alignment: .top, spacing: 6) {
                        if showSeriesMeta, let series = recording.seriesInfo {
                            Text(series.shortDisplayString)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }

                        Text(recording.cleanName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        if recording.isLiveBroadcast { LiveBadge() }
                        if recording.isNew { NewBadge() }
                    }

                    if showSeriesDescriptionOneLine,
                       showSeriesMeta,
                       let desc = recording.desc?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !desc.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            if hideSeriesChannelName,
                               showSeriesMeta,
                               let size = recording.fileSizeFormatted {
                                Text(size)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Row 2: Channel name | File size
                    if (recording.channel != nil && !(hideSeriesChannelName && showSeriesMeta)) ||
                        (recording.fileSizeFormatted != nil && !(hideSeriesChannelName && showSeriesMeta)) {
                        HStack {
                            if !(hideSeriesChannelName && showSeriesMeta),
                               let channel = recording.channel {
                                Text(channel)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if !(hideSeriesChannelName && showSeriesMeta),
                               let size = recording.fileSizeFormatted {
                                Text(size)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    // Row 3: Date + time range | Duration
                    HStack {
                        if let start = recording.startDate {
                            if let end = recording.endDate {
                                Text("\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            } else {
                                Text(start.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                        if let duration = recording.durationMinutes {
                            Text("\(duration) min")
                                .font(.caption)
                                .foregroundStyle(durationVerified ? Theme.success : Theme.textTertiary)
                        }
                    }
                }

                // Row 4: Duration mismatch warning
                if let mismatch = durationMismatch {
                    durationWarningLabel(recording: recording, mismatch: mismatch)
                } else if durationUnverifiable {
                    durationUnverifiableLabel()
                }

                // Row 5: Recording progress bar
                if recording.recordingStatus == .recording {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if let progress = recordingProgress(at: context.date) {
                            RecordingProgressBar(progress: progress)
                        }
                    }
                }
            }
        }
        .padding(.vertical, Theme.spacingSM)
        .accessibilityIdentifier("recording-row-\(recording.id)")
    }

    private var statusIcon: some View {
        RecordingStatusIcon(recording: recording, size: 44)
    }
}

#Preview {
    List {
        RecordingRow(recording: .preview)
        RecordingRow(recording: .scheduledPreview)
    }
    .listStyle(.plain)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
