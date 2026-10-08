//
//  MacDownloadsHeader.swift
//  nextpvr-apple-client
//
//  The macOS Downloads header: how many downloads there are, the space they
//  take, and how many are still running.
//

#if os(macOS)
import SwiftUI

struct MacDownloadsHeader: View {
    let count: Int
    let totalBytes: Int64
    let activeCount: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline")
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text("Downloads")
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
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
        var parts = ["\(count) download\(count == 1 ? "" : "s")"]
        if totalBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
        }
        if activeCount > 0 {
            parts.append("\(activeCount) in progress")
        }
        return parts.joined(separator: " · ")
    }
}
#endif
