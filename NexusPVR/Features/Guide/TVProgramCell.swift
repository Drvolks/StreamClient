//
//  TVProgramCell.swift
//  nextpvr-apple-client
//
//  A program in the tvOS guide grid (Midnight). Same states as the macOS
//  cell: a plate when upcoming, faded once past, the accent field while on
//  air; the focused cell inverts, as a selected macOS cell does. A topic
//  match adds an outline, a leading bar and a tag.
//

#if os(tvOS)
import SwiftUI

struct TVProgramCell: View {
    let program: Program
    let width: CGFloat
    let height: CGFloat
    let isFocused: Bool
    var isScheduled = false
    var isRecording = false
    var isCatchupAvailable = false
    var matchedTopic: String?

    @Environment(\.colorScheme) private var colorScheme

    private var isAiring: Bool { program.isCurrentlyAiring }
    /// Badges need room next to the time; narrow cells use one-letter ones.
    private var compactBadges: Bool { width < 300 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(program.cleanName)
                .font(.archivo(Theme.scaledFont(19), .extraBold))
                .foregroundStyle(titleInk)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(GuideCellTimeLabel.text(start: program.startDate, end: program.endDate, width: width / 1.6))
                    .midnightMeta(Theme.scaledFont(15))
                    .foregroundStyle(metaInk)
                    .lineLimit(1)
                    .layoutPriority(1)
                badges
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(width: max(width - 2, 60), height: height, alignment: .leading)
        .background(fill)
        .overlay(alignment: .leading) {
            if let bar = barColor {
                Rectangle().fill(bar).frame(width: 5)
            }
        }
        .overlay {
            if matchedTopic != nil {
                Rectangle().strokeBorder(MidnightPalette.topic, lineWidth: 3)
            }
        }
        .clipped()
        .scaleEffect(isFocused ? 1.02 : 1.0, anchor: .leading)
        .shadow(color: isFocused ? .black.opacity(0.35) : .clear, radius: 10, y: 4)
        .zIndex(isFocused ? 1 : 0)
        .animation(.easeInOut(duration: 0.14), value: isFocused)
    }

    @ViewBuilder
    private var fill: some View {
        if isFocused {
            MidnightPalette.selectedBg
        } else if isRecording {
            Theme.recording.opacity(0.3)
        } else if isAiring {
            MidnightGradients.field(colorScheme)
        } else if program.hasEnded {
            MidnightPalette.cellPast
        } else {
            MidnightPalette.cellRest
        }
    }

    private var badges: some View {
        HStack(spacing: 5) {
            if program.shouldShowLiveBadge { LiveBadge(compact: compactBadges) }
            if program.shouldShowNewBadge && !isCatchupAvailable { NewBadge(compact: compactBadges) }
            if isScheduled { RecBadge(isActive: isRecording, compact: compactBadges) }
            if isCatchupAvailable { CatchupBadge(compact: compactBadges) }
            if let matchedTopic, !compactBadges {
                Text(matchedTopic)
                    .badgeLabel()
                    .foregroundStyle(MidnightPalette.topicInk)
                    .background(MidnightPalette.topic)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }

    /// Leading bar: a topic match outranks focus, which outranks on-air.
    private var barColor: Color? {
        if matchedTopic != nil { return MidnightPalette.topic }
        if isFocused { return MidnightPalette.accent }
        if isAiring && !isRecording { return MidnightPalette.accentSoft }
        return nil
    }

    private var titleInk: Color {
        if isFocused { return MidnightPalette.selectedInk }
        if isAiring && !isRecording { return MidnightPalette.fieldInk }
        if program.hasEnded { return MidnightPalette.cellPastInk }
        return MidnightPalette.cellRestInk
    }

    private var metaInk: Color {
        if isFocused { return MidnightPalette.selectedSub }
        if isAiring && !isRecording { return MidnightPalette.fieldInk.opacity(0.85) }
        if program.hasEnded { return MidnightPalette.cellPastInk }
        return MidnightPalette.cellRestSub
    }
}
#endif
