//
//  MacGuideChannelCell.swift
//  nextpvr-apple-client
//
//  A channel in the pinned macOS guide column (see `MidnightChannelPlate`).
//  Clicking plays the channel.
//

#if os(macOS)
import SwiftUI

struct MacGuideChannelCell: View {
    let channel: Channel
    let iconURL: URL?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            MidnightChannelPlate(channel: channel, iconURL: iconURL)
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
