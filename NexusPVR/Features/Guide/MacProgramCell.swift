//
//  MacProgramCell.swift
//  nextpvr-apple-client
//
//  A program in the macOS guide grid (Midnight). Upcoming cells rest on a
//  lifted plate, past ones fade, the airing one sits on the accent field and
//  a selected one inverts. A topic match adds a badge.
//

#if os(macOS)
import SwiftUI

struct MacProgramCell: View {
    let program: Program
    let width: CGFloat
    let height: CGFloat
    var isScheduledRecording = false
    var isCurrentlyRecording = false
    var isCatchupAvailable = false
    /// The topic keyword this program matches, if any.
    var matchedTopic: String?
    var isSelected = false
    /// Pushes the text of an airing program to the visible left edge.
    var leadingPadding: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var isAiring: Bool { program.isCurrentlyAiring }

    private var contentWidth: CGFloat {
        width - (isAiring ? leadingPadding : 0)
    }

    private var showsBadges: Bool {
        GuideCellTimeLabel.showsBadges(width: contentWidth)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            fill

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(program.cleanName)
                        .font(.archivo(12.5, .extraBold))
                        .foregroundStyle(titleInk)
                        .lineLimit(1)
                    metaRow
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10 + (isAiring ? leadingPadding : 0))
            .padding(.trailing, 8)
        }
        .frame(width: max(width - 2, 0), height: height)
        .overlay(alignment: .leading) {
            if let barColor {
                Rectangle().fill(barColor).frame(width: 4)
            }
        }
        .overlay {
            if isHovering && !isSelected {
                Rectangle().strokeBorder(MidnightPalette.accent.opacity(0.7), lineWidth: 1)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    // MARK: Layers

    @ViewBuilder
    private var fill: some View {
        if isSelected {
            MidnightPalette.selectedBg
        } else if isCurrentlyRecording {
            Theme.recording.opacity(0.3)
        } else if isAiring {
            MidnightGradients.field(colorScheme)
        } else if program.hasEnded {
            MidnightPalette.cellPast
        } else if isHovering {
            ZStack {
                MidnightPalette.cellRest
                MidnightPalette.hoverTint
            }
        } else {
            MidnightPalette.cellRest
        }
    }

    private var metaRow: some View {
        HStack(spacing: 5) {
            Text(GuideCellTimeLabel.text(start: program.startDate, end: program.endDate, width: contentWidth))
                .midnightMeta(10.5)
                .foregroundStyle(metaInk)
                .lineLimit(1)
                .layoutPriority(1)

            if showsBadges {
                badges
            }
        }
    }

    /// Badges keep their natural size; a cell too narrow for all of them clips
    /// the last ones rather than squashing them.
    private var badges: some View {
        HStack(spacing: 5) {
            if program.shouldShowLiveBadge {
                LiveBadge(compact: false)
            }
            if program.shouldShowNewBadge && !isCatchupAvailable {
                NewBadge(compact: true)
            }
            if isCurrentlyRecording || isScheduledRecording {
                RecBadge(isActive: isCurrentlyRecording, compact: true)
            }
            if isCatchupAvailable {
                CatchupBadge(compact: true)
            }
            if let matchedTopic {
                Text(matchedTopic)
                    .midnightBadge(8.5)
                    .foregroundStyle(MidnightPalette.topicInk)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(MidnightPalette.topic)
            }
        }
        .fixedSize()
    }

    // MARK: Colours

    /// The 4pt leading bar indicates the selected or airing state.
    private var barColor: Color? {
        if isSelected { return MidnightPalette.accent }
        if isAiring && !isCurrentlyRecording { return MidnightPalette.accentSoft }
        return nil
    }

    private var titleInk: Color {
        if isSelected { return MidnightPalette.selectedInk }
        if isAiring && !isCurrentlyRecording { return MidnightPalette.fieldInk }
        if program.hasEnded { return MidnightPalette.cellPastInk }
        return MidnightPalette.cellRestInk
    }

    private var metaInk: Color {
        if isSelected { return MidnightPalette.selectedSub }
        if isAiring && !isCurrentlyRecording { return MidnightPalette.fieldInk.opacity(0.85) }
        if program.hasEnded { return MidnightPalette.cellPastInk }
        return MidnightPalette.cellRestSub
    }
}
#endif
