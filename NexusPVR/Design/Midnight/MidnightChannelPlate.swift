//
//  MidnightChannelPlate.swift
//  nextpvr-apple-client
//
//  A channel's logo on its plate. The name only shows when there is no logo.
//  Used by the guide column and the channel cards (macOS, tvOS).
//

#if os(macOS) || os(tvOS)
import SwiftUI

struct MidnightChannelPlate: View {
    let channel: Channel
    let iconURL: URL?
    var logoInsets = EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22)
    /// Size of the name shown when there is no logo; tvOS passes a TV size.
    var nameSize: CGFloat = 13

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
                #if os(macOS)
                ProgressView().controlSize(.small)
                #else
                ProgressView()
                #endif
            } fallback: {
                Text(channel.name)
                    .font(.archivo(nameSize, .extraBold))
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
