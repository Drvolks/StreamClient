//
//  MacGuideDetailBar.swift
//  nextpvr-apple-client
//
//  The bar under the macOS guide grid showing the selected program and what
//  can be done with it.
//

#if os(macOS)
import SwiftUI

struct MacGuideDetailBar: View {
    /// What the primary button does for the selected program.
    enum PrimaryAction {
        case watchLive
        case watchReplay
    }

    let program: Program?
    let channel: Channel?
    var primaryAction: PrimaryAction?
    /// "Record" or "Cancel Recording", or nil when recording isn't offered.
    var recordTitle: String?
    let onPrimary: () -> Void
    let onRecord: () -> Void
    let onDetails: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacingLG) {
            if let program, let channel {
                details(program: program, channel: channel)
                Spacer(minLength: Theme.spacingMD)
                actions
            } else {
                Text("Select a programme to see what's on and what you can do with it.")
                    .font(.archivo(12.5))
                    .foregroundStyle(MidnightPalette.inkSoft)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: program == nil ? 56 : 112)
        .background(MidnightPalette.railHead)
        .overlay(alignment: .top) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
        .accessibilityIdentifier("guide-detail-bar")
    }

    private func details(program: Program, channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(channel.name)
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accentSoft)
                if program.isCurrentlyAiring {
                    MidnightFieldChip(text: "Live now", size: 9)
                }
                if program.shouldShowLiveBadge {
                    LiveBadge()
                }
            }
            Text(program.cleanName)
                .font(.archivo(21, .extraBold))
                .tracking(-0.2)
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)
            Text(timeLine(for: program))
                .midnightMeta(11.5)
                .foregroundStyle(MidnightPalette.inkSoft)
            if let synopsis = program.desc ?? program.subtitle, !synopsis.isEmpty {
                Text(synopsis)
                    .font(.archivo(12.5))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(2)
                    .frame(maxWidth: 640, alignment: .leading)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                if let primaryAction {
                    Button(primaryAction == .watchLive ? "Watch now" : "Watch replay", action: onPrimary)
                        .buttonStyle(MidnightFieldButtonStyle())
                }
                if let recordTitle {
                    Button(recordTitle, action: onRecord)
                        .buttonStyle(MidnightOutlineButtonStyle())
                }
                Button("Details", action: onDetails)
                    .buttonStyle(MidnightOutlineButtonStyle())
            }
            Button("Clear selection", action: onClear)
                .buttonStyle(MidnightGhostButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .fixedSize()
    }

    private func timeLine(for program: Program) -> String {
        let times = GuideCellTimeLabel.text(
            start: program.startDate,
            end: program.endDate,
            width: GuideCellTimeLabel.fullWidth
        )
        return "\(times) · \(program.durationMinutes) min"
    }
}
#endif
