//
//  MacRecordingRow.swift
//  nextpvr-apple-client
//
//  A recording in the macOS list (Midnight): episode chip, title and topic,
//  air time and channel, description, resume bar; on the right the watch
//  state, duration and size, then an action strip.
//

#if os(macOS)
import SwiftUI

struct MacRecordingRow: View {
    let recording: Recording
    var matchedTopic: String?
    /// Inside a series section or page, lead with the episode title: the
    /// recording's own name is just the series name again.
    var showsEpisodeTitle = false
    /// Resumes a part-watched recording, plays any other from the start.
    let onPlay: () -> Void
    let onPlayFromBeginning: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private static let airTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var status: RecordingStatus { recording.recordingStatus }
    private var watchState: RecordingWatchState { RecordingWatchState(recording) }

    private var resumeProgress: Double? {
        if case .resume(let progress) = watchState { return progress }
        return nil
    }

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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recording-row-\(recording.id)")
    }

    // MARK: Left

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let series = recording.seriesInfo {
                    Text(series.shortDisplayString)
                        .midnightMeta(11, weight: .heavy)
                        .foregroundStyle(MidnightPalette.accentSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MidnightPalette.barSoft, in: Theme.badgeShape)
                }
                Text(title)
                    .font(.archivo(15.5, .extraBold))
                    .foregroundStyle(MidnightPalette.ink)
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
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
            }

            if let desc = description {
                Text(desc)
                    .font(.archivo(12.5))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            if let resumeProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(MidnightPalette.barSoft)
                        Rectangle()
                            .fill(MidnightGradients.field(colorScheme))
                            .frame(width: geo.size.width * resumeProgress)
                    }
                }
                .frame(width: 260, height: 3)
                .padding(.top, 2)
                .accessibilityLabel("\(Int(resumeProgress * 100)) percent watched")
            }
        }
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
        VStack(alignment: .trailing, spacing: 6) {
            stateChip
            if let minutes = recording.durationMinutes {
                Text("\(minutes) min")
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
            }
            if let size = recording.fileSizeFormatted {
                Text(size)
                    .midnightMeta(11)
                    .foregroundStyle(MidnightPalette.inkSoft)
            }
        }
        .frame(width: 104, alignment: .trailing)
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

    private var actionStrip: some View {
        let playable = status.isPlayable || status == .recording
        // Starting over only means something once the recording has been played.
        let canStartOver = playable && watchState != .new
        return HStack(spacing: 0) {
            MidnightActionCell(
                systemImage: "play.fill",
                help: resumeProgress != nil ? "Resume" : "Play",
                isEnabled: playable,
                isDimmed: !playable,
                action: onPlay
            )
            divider
            MidnightActionCell(
                systemImage: "gobackward",
                help: "Play from the beginning",
                isEnabled: canStartOver,
                isDimmed: !canStartOver,
                action: onPlayFromBeginning
            )
            divider
            MidnightActionCell(systemImage: "info.circle", help: "Info", action: onInfo)
            divider
            MidnightActionCell(
                systemImage: "trash",
                help: status.isScheduled ? "Cancel recording" : "Delete",
                hoverFill: MidnightPalette.danger,
                action: onDelete
            )
        }
        .frame(width: 34 * 4 + 3, height: 34)
        .overlay { Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
    }

    private var divider: some View {
        Rectangle().fill(MidnightPalette.lineSoft).frame(width: 1)
    }
}
#endif
