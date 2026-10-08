//
//  MacGuideChannelCell.swift
//  nextpvr-apple-client
//
//  A channel in the pinned macOS guide column: the logo on its plate, with
//  the channel's group in the top-left corner and its number bottom-right.
//  The name only shows when there is no logo. Clicking plays the channel.
//

#if os(macOS)
import SwiftUI

struct MacGuideChannelCell: View {
    let channel: Channel
    let iconURL: URL?
    let groupName: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle().fill(MidnightGradients.channelPlate(colorScheme))

                CachedAsyncImage(url: iconURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                } placeholder: {
                    ProgressView().controlSize(.small)
                } fallback: {
                    Text(channel.name)
                        .font(.archivo(13, .extraBold))
                        .textCase(.uppercase)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Color(hex: "#f4f7ff"))
                        .padding(.horizontal, 12)
                }
            }
            .overlay(alignment: .topLeading) {
                if let groupName {
                    Text(groupName)
                        .midnightBadge(8.5)
                        .foregroundStyle(Color(hex: "#f4f7ff"))
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
            .overlay {
                if isHovering {
                    Rectangle().strokeBorder(MidnightPalette.accent, lineWidth: 2)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(MidnightPalette.line).frame(width: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Watch \(channel.name)")
        .accessibilityLabel("Watch \(channel.name)")
        .accessibilityIdentifier("guide-channel-\(channel.id)")
    }
}
#endif
