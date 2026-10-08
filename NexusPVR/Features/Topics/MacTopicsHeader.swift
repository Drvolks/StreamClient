//
//  MacTopicsHeader.swift
//  nextpvr-apple-client
//
//  The macOS Topics header: the selected topic, how many programs match,
//  and a way into the keyword editor.
//

#if os(macOS)
import SwiftUI

struct MacTopicsHeader: View {
    let title: String
    let programCount: Int
    let onManage: () -> Void

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

            Button("Manage topics", action: onManage)
                .buttonStyle(MidnightOutlineButtonStyle())
                .accessibilityIdentifier("topics-manage-button")
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
