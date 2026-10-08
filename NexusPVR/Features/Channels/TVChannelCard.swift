//
//  TVChannelCard.swift
//  nextpvr-apple-client
//
//  A channel in the tvOS Channels grid (Midnight): logo band, name, status
//  tags, what's on now with its progress and end time. The card is one
//  focusable button (select plays), so it has no action strip; focus is drawn
//  by ChannelGridCardButtonStyle.
//

#if os(tvOS)
import SwiftUI

struct TVChannelCard: View {
    let channel: Channel
    let iconURL: URL?
    let currentProgram: Program?
    /// Re-read once a minute by the page, so progress stays current.
    let now: Date
    var matchedTopic: String?
    var isScheduledRecording = false
    var isCurrentlyRecording = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MidnightChannelPlate(
                channel: channel,
                iconURL: iconURL,
                logoInsets: EdgeInsets(top: 14, leading: 40, bottom: 14, trailing: 40),
                nameSize: Theme.scaledFont(22)
            )
            .frame(height: Theme.scaledMetric(96))

            VStack(alignment: .leading, spacing: 8) {
                Text(channel.name)
                    .font(.archivo(Theme.scaledFont(21), .extraBold))
                    .textCase(.uppercase)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)

                tags

                if let program = currentProgram {
                    Text(program.cleanName)
                        .font(.archivo(Theme.scaledFont(17)))
                        .foregroundStyle(MidnightPalette.cellRestSub)
                        .lineLimit(2, reservesSpace: true)
                    progressBar(program.progress(at: now))
                    Text("until \(GuideCellTimeLabel.time(program.endDate))")
                        .midnightMeta(Theme.scaledFont(14))
                        .foregroundStyle(MidnightPalette.inkFaint)
                } else {
                    Text("No program info")
                        .font(.archivo(Theme.scaledFont(17)))
                        .foregroundStyle(MidnightPalette.inkFaint)
                        .lineLimit(2, reservesSpace: true)
                    progressBar(0).hidden()
                    Text(" ").midnightMeta(Theme.scaledFont(14)).hidden()
                }
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MidnightPalette.cellRest)
        .overlay {
            Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1)
        }
    }

    /// Fixed height, so cards stay level whether or not they carry tags.
    private var tags: some View {
        HStack(spacing: 6) {
            if currentProgram?.shouldShowLiveBadge == true { LiveBadge() }
            if currentProgram?.shouldShowNewBadge == true { NewBadge() }
            if isScheduledRecording { RecBadge(isActive: isCurrentlyRecording) }
            if let matchedTopic {
                Text(matchedTopic)
                    .badgeLabel()
                    .foregroundStyle(MidnightPalette.topicInk)
                    .background(MidnightPalette.topic)
                    .lineLimit(1)
            }
        }
        .frame(height: Theme.scaledMetric(20), alignment: .leading)
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
        .frame(height: 4)
    }
}
#endif
