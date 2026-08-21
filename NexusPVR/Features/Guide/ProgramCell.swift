//
//  ProgramCell.swift
//  nextpvr-apple-client
//
//  Individual program cell in the EPG grid
//

import SwiftUI

struct ProgramCell: View {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    let program: Program
    let width: CGFloat
    var isScheduledRecording: Bool = false
    var isCurrentlyRecording: Bool = false
    var matchesKeyword: Bool = false
    var detectedSport: Sport? = nil
    var leadingPadding: CGFloat = 0 // Padding for portion that's off-screen to the left

    private var showSportIcon: Bool {
        guard detectedSport != nil else { return false }
        #if os(tvOS)
        return width > 200
        #else
        return width > 100
        #endif
    }

    /// tvOS runs the guide noticeably smaller than the platform's semantic
    /// `.caption` (~25pt), which crowded long program names out of a cell
    /// at typical channel widths. iOS / macOS keep the semantic styles
    /// they've always used. Both tvOS sizes follow the Text Size setting
    /// (#107).
    private var titleFont: Font {
        #if os(tvOS)
        .tvScaled(size: 20, weight: .medium)
        #else
        .caption
        #endif
    }

    private var timeFont: Font {
        #if os(tvOS)
        .tvScaled(size: 17)
        #else
        .caption2
        #endif
    }

    /// Room left for the start/end time + badges after the leading padding
    /// (applied to currently-airing programs to keep text pinned to the
    /// visible scroll position) eats into the cell's nominal width.
    private var effectiveWidth: CGFloat {
        width - (program.isCurrentlyAiring ? leadingPadding : 0)
    }

    /// Below this, "NEW" / "REC" next to the time text would wrap onto a
    /// second line, so fall back to single-letter badges instead.
    /// (ProgramCell is only used on iOS/macOS; tvOS renders its own cell in
    /// GuideView.swift.)
    private var useCompactBadges: Bool {
        effectiveWidth < 180
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background
            backgroundView

            // Content - padded to align with visible portion
            HStack(spacing: 4) {
                if showSportIcon, let sport = detectedSport {
                    SportIconView(sport: sport, size: Theme.cellHeight - Theme.spacingXS * 2 - 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(program.cleanName)
                        .font(titleFont)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(timeString)
                            .font(timeFont)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)

                        if program.isNew {
                            NewBadge(compact: useCompactBadges)
                        }

                        if isCurrentlyRecording || isScheduledRecording {
                            RecBadge(isActive: isCurrentlyRecording, compact: useCompactBadges)
                        }
                    }
                }

                Spacer(minLength: 0)

            }
            .padding(.leading, Theme.spacingSM + (program.isCurrentlyAiring ? leadingPadding : 0))
            .padding(.trailing, Theme.spacingSM)
            .padding(.vertical, Theme.spacingXS)

            // Progress indicator for currently airing
            if program.isCurrentlyAiring {
                progressOverlay
            }
        }
        .frame(width: width, height: Theme.cellHeight - 2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        .overlay {
            if matchesKeyword {
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM)
                    .strokeBorder(Color(red: 0.8, green: 0.7, blue: 0.3).opacity(0.6), lineWidth: 2)
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if program.hasEnded {
            Theme.guidePast
        } else if isCurrentlyRecording {
            Theme.recording.opacity(0.3)
        } else if program.isCurrentlyAiring {
            Theme.guideNowPlaying
        } else if isScheduledRecording {
            Theme.guideScheduled
        } else {
            Theme.surfaceHighlight
        }
    }

    private var progressOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Theme.accent.opacity(0.3))
                .frame(width: geo.size.width * program.progress())
        }
    }

    private var timeString: String {
        "\(Self.timeFormatter.string(from: program.startDate)) - \(Self.timeFormatter.string(from: program.endDate))"
    }
}

#Preview {
    VStack(spacing: Theme.spacingMD) {
        ProgramCell(program: .preview, width: 200)

        ProgramCell(
            program: Program(
                id: 2,
                name: "Past Show",
                subtitle: "Episode 5",
                desc: nil,
                start: Int(Date().addingTimeInterval(-7200).timeIntervalSince1970),
                end: Int(Date().addingTimeInterval(-3600).timeIntervalSince1970),
                genres: nil,
                channelId: 1
            ),
            width: 200
        )

        ProgramCell(
            program: Program(
                id: 3,
                name: "Future Show",
                subtitle: nil,
                desc: nil,
                start: Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
                end: Int(Date().addingTimeInterval(7200).timeIntervalSince1970),
                genres: nil,
                channelId: 1
            ),
            width: 200,
            isScheduledRecording: true
        )
    }
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
