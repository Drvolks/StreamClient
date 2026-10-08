//
//  MidnightSectionHeader.swift
//  nextpvr-apple-client
//
//  Heads a block of a macOS Midnight list (a series of recordings, a day of
//  topic matches): an uppercase title, a mono meta line and a 2pt rule.
//

#if os(macOS)
import SwiftUI

struct MidnightSectionHeader: View {
    let title: String
    let meta: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.archivo(17, .extraBold))
                .textCase(.uppercase)
                .foregroundStyle(MidnightPalette.ink)
                .lineLimit(1)
            Text(meta)
                .midnightMeta(11)
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
#endif
