//
//  TVRecordingRow.swift
//  nextpvr-apple-client
//
//  A recording in the tvOS lists (Midnight): episode chip, title, LIVE and
//  topic tags, air time and channel, description, then a resume or
//  recording-progress bar; on the right the watch state, duration and size.
//  The macOS row's action strip has no tvOS equivalent: select plays (or
//  opens the details), and the context menu has the rest. Used as the
//  label of a Button styled with TVMidnightButtonStyle; when focused the
//  row inverts, like a focused guide cell.
//

#if os(tvOS)
import SwiftUI

struct TVRecordingRow: View {
    let recording: Recording
    var matchedTopic: String?
    /// Inside a series section or page, lead with the episode title: the
    /// recording's own name is just the series name again.
    var showsEpisodeTitle = false
    /// A duration problem found while checking the stream, if any.
    var durationWarning: String?

    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    private static let airTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var status: RecordingStatus { recording.recordingStatus }
    private var watchState: RecordingWatchState { RecordingWatchState(recording) }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingLG) {
            details
            Spacer(minLength: Theme.spacingSM)
            facts
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? MidnightPalette.selectedBg : MidnightPalette.cellRest)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle().fill(MidnightPalette.accent).frame(width: 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recording-row-\(recording.id)")
    }

    // MARK: Left

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                if let series = recording.seriesInfo {
                    Text(series.shortDisplayString)
                        .midnightMeta(Theme.scaledFont(16), weight: .heavy)
                        .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accentSoft)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(isFocused ? MidnightPalette.selectedSub.opacity(0.2) : MidnightPalette.barSoft, in: Theme.badgeShape)
                }
                Text(title)
                    .font(.archivo(Theme.scaledFont(23), .extraBold))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                    .lineLimit(1)
                if recording.isLiveBroadcast {
                    LiveBadge()
                }
                if let matchedTopic {
                    Text(matchedTopic)
                        .lineLimit(1)
                        .badgeLabel()
                        .foregroundStyle(MidnightPalette.topicInk)
                        .background(MidnightPalette.topic, in: Theme.badgeShape)
                }
            }

            if let meta = metaLine {
                Text(meta)
                    .midnightMeta(Theme.scaledFont(16))
                    .foregroundStyle(subInk)
                    .lineLimit(1)
            }

            if let desc = description {
                Text(desc)
                    .font(.archivo(Theme.scaledFont(18)))
                    .foregroundStyle(subInk)
                    .lineLimit(2)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            if let durationWarning {
                Label(durationWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.archivo(Theme.scaledFont(15), .extraBold))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : Theme.warning)
                    .lineLimit(1)
            }

            if status == .recording {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let progress = recordingProgress(at: context.date) {
                        progressBar(progress, fill: AnyShapeStyle(Theme.recording))
                    }
                }
            } else if case .resume(let progress) = watchState {
                progressBar(progress, fill: AnyShapeStyle(MidnightGradients.field(colorScheme)))
                    .accessibilityLabel("\(Int(progress * 100)) percent watched")
            }
        }
    }

    private var subInk: Color {
        isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkSoft
    }

    private func progressBar(_ fraction: Double, fill: AnyShapeStyle) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(isFocused ? MidnightPalette.selectedSub.opacity(0.25) : MidnightPalette.barSoft)
                Rectangle()
                    .fill(fill)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(width: 420, height: 5)
        .padding(.top, 3)
    }

    private func recordingProgress(at date: Date) -> Double? {
        guard let start = recording.recordingStartTime,
              let total = recording.totalRecordingDuration,
              total > 0 else { return nil }
        return min(max((date.timeIntervalSince1970 - Double(start)) / Double(total), 0), 1)
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let start = recording.startDate {
            parts.append(Self.airTimeFormatter.string(from: start).replacingOccurrences(of: " at ", with: " · "))
        }
        if let channel = recording.channel, !channel.isEmpty {
            parts.append(channel)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var title: String {
        if showsEpisodeTitle, let episode = recording.episodeTitle { return episode }
        return recording.cleanName
    }

    private var description: String? {
        // The subtitle is already the title when the episode title leads.
        let candidates = showsEpisodeTitle && recording.episodeTitle != nil
            ? [recording.desc]
            : [recording.subtitle, recording.desc]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    // MARK: Right

    private var facts: some View {
        VStack(alignment: .trailing, spacing: 8) {
            stateChip
            if let minutes = recording.durationMinutes {
                Text("\(minutes) min")
                    .midnightMeta(Theme.scaledFont(16))
                    .foregroundStyle(subInk)
            }
            if let size = recording.fileSizeFormatted {
                Text(size)
                    .midnightMeta(Theme.scaledFont(16))
                    .foregroundStyle(subInk)
            }
        }
        .frame(minWidth: 150, alignment: .trailing)
    }

    @ViewBuilder
    private var stateChip: some View {
        let size = Theme.scaledFont(14)
        switch status {
        case .recording:
            Text("Recording")
                .midnightBadge(size)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.recording, in: Theme.badgeShape)
        case .pending, .conflict:
            Text(status == .conflict ? "Conflict" : "Scheduled")
                .midnightBadge(size)
                .foregroundStyle(status == .conflict ? MidnightPalette.danger : subInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay { Theme.badgeShape.strokeBorder(isFocused ? MidnightPalette.selectedSub : MidnightPalette.line, lineWidth: 1) }
        case .failed:
            Text("Failed")
                .midnightBadge(size)
                .foregroundStyle(MidnightPalette.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay { Theme.badgeShape.strokeBorder(MidnightPalette.danger, lineWidth: 1) }
        default:
            WatchStateChip(state: watchState, size: size)
        }
    }
}
#endif
