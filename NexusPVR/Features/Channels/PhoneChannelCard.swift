//
//  PhoneChannelCard.swift
//  nextpvr-apple-client
//
//  A channel in the iOS Channels grid (Midnight): logo band, name, status
//  tags, what's on now with its progress and end time, and the same action
//  strip as on macOS (watch, watch from the beginning, record, info).
//  Tapping the card above the strip also watches.
//

#if os(iOS)
import SwiftUI

struct PhoneChannelCard: View {
    let channel: Channel
    let iconURL: URL?
    let currentProgram: Program?
    /// Re-read once a minute by the page, so progress stays current.
    let now: Date
    var matchedTopic: String?
    var isScheduledRecording = false
    var isCurrentlyRecording = false
    /// Whether "watch from the beginning" can play anything right now.
    var canWatchFromStart = false
    var showsRecord = true
    let onWatch: () -> Void
    let onWatchFromStart: () -> Void
    let onRecord: () -> Void
    let onInfo: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onWatch) {
                summary
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("channel-card-\(channel.id)")

            actionStrip
        }
        .background(MidnightPalette.cellRest)
        .clipShape(shape)
        .overlay { shape.strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            MidnightChannelPlate(
                channel: channel,
                iconURL: iconURL,
                logoInsets: EdgeInsets(top: 10, leading: 26, bottom: 10, trailing: 26),
                nameSize: 13
            )
            .frame(height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(channel.name)
                    .font(.archivo(14, .extraBold))
                    .textCase(.uppercase)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)

                tags

                if let program = currentProgram {
                    Text(program.cleanName)
                        .font(.archivo(12.5))
                        .foregroundStyle(MidnightPalette.cellRestSub)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    progressBar(program.progress(at: now))
                    Text("until \(GuideCellTimeLabel.time(program.endDate))")
                        .midnightMeta(10)
                        .foregroundStyle(MidnightPalette.inkFaint)
                } else {
                    Text("No program info")
                        .font(.archivo(12.5))
                        .foregroundStyle(MidnightPalette.inkFaint)
                        .lineLimit(2, reservesSpace: true)
                    progressBar(0).hidden()
                    Text(" ").midnightMeta(10).hidden()
                }
            }
            .padding(EdgeInsets(top: 9, leading: 11, bottom: 11, trailing: 11))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionStrip: some View {
        let hasProgram = currentProgram != nil
        return HStack(spacing: 0) {
            MidnightActionCell(systemImage: "play.fill", help: "Watch", action: onWatch)
            #if DISPATCHERPVR
            divider
            MidnightActionCell(
                systemImage: "gobackward",
                help: "Watch from the beginning",
                isEnabled: canWatchFromStart,
                isDimmed: !hasProgram,
                action: onWatchFromStart
            )
            #endif
            if showsRecord {
                divider
                MidnightActionCell(
                    systemImage: isScheduledRecording ? "record.circle.fill" : "record.circle",
                    help: isScheduledRecording ? "Cancel recording" : "Record",
                    isEnabled: hasProgram,
                    isDimmed: !hasProgram,
                    action: onRecord
                )
            }
            divider
            MidnightActionCell(
                systemImage: "info.circle",
                help: "Info",
                isEnabled: hasProgram,
                isDimmed: !hasProgram,
                action: onInfo
            )
        }
        .frame(height: 40)
        .overlay(alignment: .top) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
    }

    private var divider: some View {
        Rectangle().fill(MidnightPalette.lineSoft).frame(width: 1)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
    }

    /// Fixed height, so cards stay level whether or not they carry tags.
    private var tags: some View {
        HStack(spacing: 4) {
            if currentProgram?.shouldShowLiveBadge == true { LiveBadge() }
            if currentProgram?.shouldShowNewBadge == true { NewBadge() }
            if isScheduledRecording { RecBadge(isActive: isCurrentlyRecording) }
            if let matchedTopic {
                Text(matchedTopic)
                    .badgeLabel()
                    .foregroundStyle(MidnightPalette.topicInk)
                    .background(MidnightPalette.topic, in: Theme.badgeShape)
                    .lineLimit(1)
            }
        }
        .frame(height: 15, alignment: .leading)
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(MidnightPalette.barSoft)
                Rectangle()
                    .fill(MidnightGradients.field(colorScheme))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}
#endif
