//
//  PhoneRecordingRow.swift
//  nextpvr-apple-client
//
//  A recording in the iOS lists (Midnight): episode chip and title with the
//  watch state, air time and channel, tags, description, duration and size,
//  then a resume or recording-progress bar. The macOS row's action strip
//  has no room here: tap plays (or opens the details), swipe deletes, and
//  the context menu has the rest.
//

#if os(iOS)
import SwiftUI

struct PhoneRecordingRow: View {
    let recording: Recording
    var matchedTopic: String?
    /// Inside a series section or page, lead with the episode title: the
    /// recording's own name is just the series name again.
    var showsEpisodeTitle = false
    /// A duration problem found while checking the stream, if any.
    var durationWarning: String?

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
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                if let series = recording.seriesInfo {
                    Text(series.shortDisplayString)
                        .midnightMeta(10.5, weight: .heavy)
                        .foregroundStyle(MidnightPalette.accentSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MidnightPalette.barSoft, in: Theme.badgeShape)
                        .fixedSize()
                }
                Text(title)
                    .font(.archivo(16, .extraBold))
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                stateChip.fixedSize()
            }

            if let meta = metaLine {
                Text(meta)
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
            }

            if recording.isLiveBroadcast || matchedTopic != nil {
                HStack(spacing: 5) {
                    if recording.isLiveBroadcast { LiveBadge() }
                    if let matchedTopic {
                        Text(matchedTopic)
                            .lineLimit(1)
                            .badgeLabel()
                            .foregroundStyle(MidnightPalette.topicInk)
                            .background(MidnightPalette.topic, in: Theme.badgeShape)
                    }
                }
            }

            if let desc = description {
                Text(desc)
                    .font(.archivo(13))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(2)
            }

            if let durationWarning {
                Label(durationWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.archivo(11.5, .extraBold))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(2)
            }

            if let facts = factsLine {
                Text(facts)
                    .midnightMeta(10.5)
                    .foregroundStyle(MidnightPalette.inkFaint)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recording-row-\(recording.id)")
    }

    private func progressBar(_ fraction: Double, fill: AnyShapeStyle) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(MidnightPalette.barSoft)
                Rectangle()
                    .fill(fill)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
        .padding(.top, 2)
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

    private var factsLine: String? {
        var parts: [String] = []
        if let minutes = recording.durationMinutes { parts.append("\(minutes) min") }
        if let size = recording.fileSizeFormatted { parts.append(size) }
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

    @ViewBuilder
    private var stateChip: some View {
        switch status {
        case .recording:
            Text("Recording")
                .midnightBadge(9)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.recording, in: Theme.badgeShape)
        case .pending, .conflict:
            Text(status == .conflict ? "Conflict" : "Scheduled")
                .midnightBadge(9)
                .foregroundStyle(status == .conflict ? MidnightPalette.danger : MidnightPalette.inkSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay { Theme.badgeShape.strokeBorder(MidnightPalette.line, lineWidth: 1) }
        case .failed:
            Text("Failed")
                .midnightBadge(9)
                .foregroundStyle(MidnightPalette.danger)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay { Theme.badgeShape.strokeBorder(MidnightPalette.danger, lineWidth: 1) }
        default:
            WatchStateChip(state: watchState)
        }
    }
}
#endif
