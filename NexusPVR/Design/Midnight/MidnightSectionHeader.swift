//
//  MidnightSectionHeader.swift
//  nextpvr-apple-client
//
//  Heads a block of a macOS Midnight list (a series of recordings, a day of
//  topic matches): an uppercase title, a mono meta line and a 2pt rule.
//  tvOS uses it too, at TV sizes.
//

import SwiftUI

struct MidnightSectionHeader: View {
    let title: String
    let meta: String

    #if os(tvOS)
    private let titleSize = Theme.scaledFont(24)
    private let metaSize = Theme.scaledFont(16)
    #else
    private let titleSize: CGFloat = 17
    private let metaSize: CGFloat = 11
    #endif

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.archivo(titleSize, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)
            Text(meta)
                .midnightMeta(metaSize)
                .foregroundStyle(MidnightPalette.inkSoft)
            Spacer()
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 2)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
