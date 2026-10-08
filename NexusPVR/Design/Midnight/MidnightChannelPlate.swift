//
//  MidnightChannelPlate.swift
//  nextpvr-apple-client
//
//  A channel's logo on its plate. The name only shows when there is no logo.
//  Used by the macOS guide column and the channel cards.
//

#if os(macOS)
import SwiftUI

struct MidnightChannelPlate: View {
    let channel: Channel
    let iconURL: URL?
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
    }
}
#endif
