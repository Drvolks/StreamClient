//
//  TVSettingsRowLabel.swift
//  nextpvr-apple-client
//
//  One row of tvOS Settings (Midnight): label, optional sub-line, and a
//  trailing value or control. The label of a Button styled with
//  TVMidnightButtonStyle; focus inverts the row with an accent bar, like the
//  other tvOS Midnight rows.
//

#if os(tvOS)
import SwiftUI

struct TVSettingsRowLabel<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.archivo(Theme.scaledFont(22), .extraBold))
                    .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.archivo(Theme.scaledFont(16)))
                        .foregroundStyle(isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkSoft)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.spacingMD)
            trailing
        }
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .padding(.vertical, 14)
        .frame(minHeight: Theme.scaledMetric(76))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? MidnightPalette.selectedBg : MidnightPalette.cellRest)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle().fill(MidnightPalette.accent).frame(width: 6)
            }
        }
    }
}

extension TVSettingsRowLabel where Trailing == TVSettingsRowValue {
    /// A row that shows its current value and opens a chooser.
    init(title: String, subtitle: String? = nil, value: String) {
        self.init(title: title, subtitle: subtitle) { TVSettingsRowValue(value: value) }
    }
}
#endif
