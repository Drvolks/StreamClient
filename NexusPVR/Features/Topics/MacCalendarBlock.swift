//
//  MacCalendarBlock.swift
//  nextpvr-apple-client
//
//  A program on the macOS Calendar timeline (Midnight), styled like a guide
//  cell: a plate when upcoming, faded once past, the accent field while on
//  air. The leading bar carries the topic's own colour.
//

#if os(macOS)
import SwiftUI

struct MacCalendarBlock: View {
    let program: Program
    let channel: Channel
    let topicColor: Color
    let height: CGFloat
    var isScheduled = false
    var isCatchupAvailable = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isAiring: Bool { program.isCurrentlyAiring }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(program.cleanName)
                .font(.archivo(12, .extraBold))
                .foregroundStyle(titleInk)
                .lineLimit(height > 44 ? 2 : 1)
            if height > 36 {
                Text("\(GuideCellTimeLabel.text(start: program.startDate, end: program.endDate, width: GuideCellTimeLabel.fullWidth)) · \(channel.name)")
                    .midnightMeta(9.5)
                    .foregroundStyle(metaInk)
                    .lineLimit(1)
            }
            if height > 58, hasBadges {
                badges
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        // Tight blocks (a short program right before another) keep their title line.
        .padding(.vertical, height > 24 ? 4 : 2)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(fill)
        .overlay(alignment: .leading) {
            Rectangle().fill(topicColor).frame(width: 4)
        }
        .overlay {
            if isHovering {
                Rectangle().strokeBorder(MidnightPalette.accent.opacity(0.7), lineWidth: 1)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var fill: some View {
        if isAiring {
            MidnightGradients.field(colorScheme)
        } else if program.hasEnded {
            MidnightPalette.cellPast
        } else {
            MidnightPalette.cellRest
        }
    }

    private var hasBadges: Bool {
        program.shouldShowLiveBadge || program.shouldShowNewBadge || isScheduled || isCatchupAvailable
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if program.shouldShowLiveBadge { LiveBadge() }
            if program.shouldShowNewBadge && !isCatchupAvailable { NewBadge() }
            if isScheduled { RecBadge(isActive: isAiring) }
            if isCatchupAvailable { CatchupBadge() }
        }
        .fixedSize()
    }

    private var titleInk: Color {
        if isAiring { return MidnightPalette.fieldInk }
        if program.hasEnded { return MidnightPalette.cellPastInk }
        return MidnightPalette.cellRestInk
    }

    private var metaInk: Color {
        if isAiring { return MidnightPalette.fieldInk.opacity(0.85) }
        if program.hasEnded { return MidnightPalette.cellPastInk }
        return MidnightPalette.cellRestSub
    }
}
#endif
