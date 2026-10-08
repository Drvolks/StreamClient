//
//  MacChannelCard.swift
//  nextpvr-apple-client
//
//  A channel in the macOS Channels grid (Midnight): logo band, what's on now
//  (always live, so it carries no LIVE badge) with its progress, and an action strip (watch, watch from the beginning,
//  record, info). Watching from the beginning is Dispatcharr-only.
//  Double-clicking the logo band also watches.
//

#if os(macOS)
import SwiftUI

struct MacChannelCard: View {
    let channel: Channel
    let iconURL: URL?
    let currentProgram: Program?
    /// Re-read once a minute by the page, so progress and "until" stay current.
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
        VStack(alignment: .leading, spacing: 0) {
            MidnightChannelPlate(
                channel: channel,
                iconURL: iconURL,
                logoInsets: EdgeInsets(top: 10, leading: 26, bottom: 10, trailing: 26)
            )
            .frame(height: 62)
            .onTapGesture(count: 2, perform: onWatch)
            .help("Double-click to watch \(channel.name)")

            programBody
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)

            actionStrip
        }
        .background(MidnightPalette.cellRest)
        .overlay {
            Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("channel-card-\(channel.id)")
    }

    // MARK: Body

    private var programBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            // On its own line, so chips never shorten it.
            Text(channel.name)
                .font(.archivo(15, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)

            chips

            if let program = currentProgram {
                Text(program.cleanName)
                    .font(.archivo(12))
                    .foregroundStyle(MidnightPalette.cellRestSub)
                    .lineLimit(2, reservesSpace: true)
                progressBar(program.progress(at: now))
                Text("until \(GuideCellTimeLabel.time(program.endDate))")
                    .midnightMeta(9.5)
                    .foregroundStyle(MidnightPalette.inkFaint)
            } else {
                Text("No program info")
                    .font(.archivo(12))
                    .foregroundStyle(MidnightPalette.inkFaint)
                    .lineLimit(2, reservesSpace: true)
                // Keep cards without EPG data level with the others.
                progressBar(0).hidden()
                Text(" ").midnightMeta(9.5).hidden()
            }
        }
    }

    private var chips: some View {
        // Fixed height, so cards stay level whether or not they carry chips.
        HStack(spacing: 5) {
            if currentProgram?.shouldShowLiveBadge == true {
                LiveBadge()
            }
            if currentProgram?.shouldShowNewBadge == true {
                NewBadge(compact: false)
            }
            if isScheduledRecording {
                RecBadge(isActive: isCurrentlyRecording)
            }
            if let matchedTopic {
                Text(matchedTopic)
                    .lineLimit(1)
                    .badgeLabel()
                    .foregroundStyle(MidnightPalette.topicInk)
                    .background(MidnightPalette.topic)
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

    // MARK: Actions

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
        .frame(height: 34)
        .overlay(alignment: .top) {
            Rectangle().fill(MidnightPalette.lineSoft).frame(height: 1)
        }
    }

    private var divider: some View {
        Rectangle().fill(MidnightPalette.lineSoft).frame(width: 1)
    }
}
#endif
