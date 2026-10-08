//
//  MidnightChannelPlate.swift
//  nextpvr-apple-client
//
//  A channel's logo on its plate, with the channel's group in the top-left
//  corner and its number bottom-right. The name only shows when there is no
//  logo. Used by the macOS guide column and the channel cards.
//

#if os(macOS)
import SwiftUI

struct MidnightChannelPlate: View {
    let channel: Channel
    let iconURL: URL?
    let groupName: String?
    var logoInsets = EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)

    @Environment(\.colorScheme) private var colorScheme

    /// Plate ink: always light, since the plate is dark in both modes.
    private static let plateInk = Color(hex: "#f4f7ff")

    var body: some View {
        ZStack {
            Rectangle().fill(MidnightGradients.channelPlate(colorScheme))

            CachedAsyncImage(url: iconURL) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .padding(logoInsets)
            } placeholder: {
                ProgressView().controlSize(.small)
            } fallback: {
                Text(channel.name)
                    .font(.archivo(13, .extraBold))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Self.plateInk)
                    .padding(.horizontal, 12)
            }
        }
        .overlay(alignment: .topLeading) {
            if let groupName {
                Text(groupName)
                    .midnightBadge(8.5)
                    .foregroundStyle(Self.plateInk)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.16))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "\(channel.number)")
                .midnightMeta(10, weight: .heavy)
                .foregroundStyle(MidnightPalette.accentSoft)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(MidnightPalette.shell)
        }
    }
}
#endif
