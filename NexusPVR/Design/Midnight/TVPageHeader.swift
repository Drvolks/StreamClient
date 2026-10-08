//
//  TVPageHeader.swift
//  nextpvr-apple-client
//
//  The tvOS page header (Midnight): a kicker over a display title and a mono
//  readout, with optional trailing controls. The tvOS counterpart of
//  MidnightPageHeader, at TV sizes.
//

#if os(tvOS)
import SwiftUI

struct TVPageHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    var readout: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker)
                    .midnightKicker(Theme.scaledFont(13))
                    .foregroundStyle(MidnightPalette.accent)
                Text(title)
                    .midnightDisplay(Theme.scaledFont(30))
                    .foregroundStyle(MidnightPalette.ink)
                    .lineLimit(1)
            }
            .fixedSize()

            if let readout {
                Text(readout)
                    .midnightMeta(Theme.scaledFont(15))
                    .foregroundStyle(MidnightPalette.inkSoft)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: Theme.spacingSM)

            trailing
        }
        .padding(.horizontal, Theme.spacingLG)
        .frame(minHeight: 78)
        .background(MidnightPalette.railHead.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MidnightPalette.line).frame(height: 1)
        }
    }
}

extension TVPageHeader where Trailing == EmptyView {
    init(kicker: String, title: String, readout: String? = nil) {
        self.init(kicker: kicker, title: title, readout: readout) { EmptyView() }
    }
}
#endif
