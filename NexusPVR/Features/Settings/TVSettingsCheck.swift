//
//  TVSettingsCheck.swift
//  nextpvr-apple-client
//
//  The tick box of a tvOS Settings row that includes or leaves out one item
//  (a channel group or profile in the sidebar).
//

#if os(tvOS)
import SwiftUI

struct TVSettingsCheck: View {
    let isOn: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isOn ? MidnightPalette.accent : Color.clear)
            Rectangle()
                .strokeBorder(isOn ? Color.clear : (isFocused ? MidnightPalette.selectedSub : MidnightPalette.line), lineWidth: 2)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: Theme.scaledFont(18), weight: .heavy))
                    .foregroundStyle(Theme.textOnAccent)
            }
        }
        .frame(width: Theme.scaledMetric(34), height: Theme.scaledMetric(34))
        .accessibilityLabel(isOn ? "Included" : "Not included")
    }
}
#endif
