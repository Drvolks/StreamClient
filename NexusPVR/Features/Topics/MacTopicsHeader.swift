//
//  MacTopicsHeader.swift
//  nextpvr-apple-client
//
//  The macOS Topics header: the selected topic and how many programs match.
//  Topics are managed in Settings › Topics.
//

#if os(macOS)
import SwiftUI

struct MacTopicsHeader: View {
    let title: String
    let programCount: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Topics")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            Text("\(programCount) program\(programCount == 1 ? "" : "s")")
                .midnightMeta(11.5)
                .foregroundStyle(MidnightPalette.inkSoft)
                .fixedSize()

            Spacer(minLength: Theme.spacingSM)
        }
        .padding(.horizontal, MacGuideHeaderMetrics.horizontalPadding)
        .frame(height: MacGuideHeaderMetrics.height)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }
}
#endif
