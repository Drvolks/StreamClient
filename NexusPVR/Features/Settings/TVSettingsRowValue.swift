//
//  TVSettingsRowValue.swift
//  nextpvr-apple-client
//
//  A tvOS Settings row's current value and chevron: the row opens a chooser.
//

#if os(tvOS)
import SwiftUI

struct TVSettingsRowValue: View {
    let value: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 12) {
            Text(value)
                .font(.archivo(Theme.scaledFont(19), .extraBold))
                .foregroundStyle(isFocused ? MidnightPalette.selectedInk : MidnightPalette.accentSoft)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: Theme.scaledFont(16), weight: .bold))
                .foregroundStyle(isFocused ? MidnightPalette.selectedSub : MidnightPalette.inkFaint)
        }
    }
}
#endif
