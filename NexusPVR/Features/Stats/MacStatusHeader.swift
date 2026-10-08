//
//  MacStatusHeader.swift
//  nextpvr-apple-client
//
//  The macOS Status header: how many channels are streaming and how many
//  M3U accounts the server has.
//

#if os(macOS) && DISPATCHERPVR
import SwiftUI

struct MacStatusHeader: View {
    let activeCount: Int
    let accountCount: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Server")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text("Status")
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
            }
            .fixedSize()

            Text(readout)
                .midnightKicker(9.5)
                .foregroundStyle(MidnightPalette.inkSoft)
                .lineLimit(1)
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

    private var readout: String {
        let streams = "\(activeCount) active channel\(activeCount == 1 ? "" : "s")"
        guard accountCount > 0 else { return streams }
        return "\(streams) · \(accountCount) M3U account\(accountCount == 1 ? "" : "s")"
    }
}
#endif
