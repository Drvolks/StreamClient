//
//  TVTopicProgramRowLabel.swift
//  nextpvr-apple-client
//
//  The face of a tvOS Topics row (Midnight), after the macOS row: title and
//  badges, time and channel, description and any earlier-recording note; on
//  the right its recording state and, when focused, what select does. What
//  is on now gets the accent bar, as in the guide; focus inverts the row.
//

#if os(tvOS)
import SwiftUI

struct TVTopicProgramRowLabel: View {
    let program: Program
    let channel: Channel
    let isRecording: Bool
    let isScheduled: Bool
    let isProcessing: Bool
    let existingRecording: Recording?
    let earlierScheduled: Recording?
    let selectAction: String

    @Environment(\.isFocused) private var isFocused

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
            } else if program.isCurrentlyAiring {
                Rectangle().fill(MidnightPalette.accentSoft).frame(width: 6)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Left

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(program.cleanName)
                    .font(.archivo(Theme.scaledFont(23), .extraBold))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                    .lineLimit(1)
                if program.shouldShowLiveBadge { LiveBadge() }
                if program.shouldShowNewBadge { NewBadge() }
            }

            Text("\(GuideCellTimeLabel.text(start: program.startDate, end: program.endDate, width: GuideCellTimeLabel.fullWidth)) · \(channel.name)")
                .midnightMeta(Theme.scaledFont(16))
                .foregroundStyle(subInk)
                .lineLimit(1)

            if let desc = description {
                Text(desc)
                    .font(.archivo(Theme.scaledFont(18)))
                    .foregroundStyle(subInk)
                    .lineLimit(2)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            if let note = earlierRecordingNote {
                Text(note)
                    .midnightMeta(Theme.scaledFont(15))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkFaint)
            }
        }
    }

    private var subInk: Color {
        isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkSoft
    }

    private var description: String? {
        [program.subtitle, program.desc]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Says when this program was already recorded, or is set to record at
    /// an earlier airing, so the user can skip this one.
    private var earlierRecordingNote: String? {
        if let existing = existingRecording, let start = existing.startDate {
            return "Already recorded · \(start.formatted(date: .abbreviated, time: .omitted)) \(GuideCellTimeLabel.time(start))"
        }
        if let earlier = earlierScheduled, let start = earlier.startDate {
            return "Recording an earlier airing · \(start.formatted(date: .abbreviated, time: .omitted)) \(GuideCellTimeLabel.time(start))"
        }
        return nil
    }

    // MARK: Right

    private var facts: some View {
        VStack(alignment: .trailing, spacing: 10) {
            stateChip
            if isProcessing {
                ProgressView()
            } else if isFocused {
                Text(selectAction)
                    .midnightKicker(Theme.scaledFont(13))
                    .foregroundStyle(MidnightPalette.selectedSub)
            }
        }
        .frame(minWidth: 180, alignment: .trailing)
    }

    @ViewBuilder
    private var stateChip: some View {
        let size = Theme.scaledFont(14)
        if isRecording {
            Text("Recording")
                .midnightBadge(size)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.recording, in: Theme.badgeShape)
        } else if isScheduled {
            Text("Scheduled")
                .midnightBadge(size)
                .foregroundStyle(subInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay { Theme.badgeShape.strokeBorder(isFocused ? MidnightPalette.selectedSub : MidnightPalette.line, lineWidth: 1) }
                .accessibilityIdentifier("scheduled-indicator")
        } else if program.isCurrentlyAiring {
            MidnightFieldChip(text: "On now", size: size)
        }
    }
}
#endif
