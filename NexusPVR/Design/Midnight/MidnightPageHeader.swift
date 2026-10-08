//
//  MidnightPageHeader.swift
//  nextpvr-apple-client
//
//  The standard macOS page header (Midnight): a kicker over a display title,
//  a mono readout, and optional trailing controls.
//

#if os(macOS)
import SwiftUI

struct MidnightPageHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    var readout: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(kicker)
                    .midnightKicker(10)
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(27)
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            if let readout {
                Text(readout)
                    .midnightKicker(9.5)
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: Theme.spacingSM)

            trailing
        }
        .padding(.horizontal, MacGuideHeaderMetrics.horizontalPadding)
        .frame(height: MacGuideHeaderMetrics.height)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }
}

extension MidnightPageHeader where Trailing == EmptyView {
    init(kicker: String, title: String, readout: String? = nil) {
        self.init(kicker: kicker, title: title, readout: readout) { EmptyView() }
    }
}
#endif
