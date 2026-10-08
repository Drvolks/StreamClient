//
//  PhoneChannelCard.swift
//  nextpvr-apple-client
//
//  A channel in the iOS Channels grid (Midnight): logo band, name, status
//  tags, what's on now with its progress and end time. The whole card is a
//  button (tap plays), as on tvOS.
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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
        .background(MidnightPalette.cellRest)
        .overlay { Rectangle().strokeBorder(MidnightPalette.lineSoft, lineWidth: 1) }
        .contentShape(Rectangle())
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
                    .background(MidnightPalette.topic)
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
