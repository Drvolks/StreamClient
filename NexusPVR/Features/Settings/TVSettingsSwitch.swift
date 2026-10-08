//
//  TVSettingsSwitch.swift
//  nextpvr-apple-client
//
//  The ON / OFF switch of a tvOS Settings row (Midnight): the track fills
//  with the accent field when on. Selecting the row flips it.
//

#if os(tvOS)
import SwiftUI

struct TVSettingsSwitch: View {
    let isOn: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Group {
                if isOn {
                    Rectangle().fill(MidnightGradients.field(colorScheme))
                } else {
                    Rectangle().fill(MidnightPalette.barSoft)
                }
            }
            Text(isOn ? "ON" : "OFF")
                .font(.archivo(Theme.scaledFont(14), .extraBold))
                .foregroundStyle(isOn ? MidnightPalette.chipInk : MidnightPalette.fieldInk)
                .frame(width: 52)
                .frame(maxHeight: .infinity)
                .background(isOn ? MidnightPalette.chipBg : MidnightPalette.inkFaint)
        }
        .frame(width: 106, height: 38)
        .overlay { Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1) }
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}
#endif
