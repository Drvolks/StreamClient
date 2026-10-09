//
//  TVSeasonChipLabel.swift
//  DispatcherPVR
//
//  One season in the tvOS season picker. The listed season carries the
//  accent field; focus inverts the chip like every other Midnight control.
//

#if os(tvOS) && DISPATCHERPVR
import SwiftUI

struct TVSeasonChipLabel: View {
    let title: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.archivo(Theme.scaledFont(17), .extraBold))
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background {
                if isFocused {
                    Rectangle().fill(MidnightPalette.selectedBg)
                } else if isSelected {
                    Rectangle().fill(MidnightGradients.field(colorScheme))
                }
            }
            .overlay {
                if !isFocused && !isSelected {
                    Rectangle().strokeBorder(MidnightPalette.line, lineWidth: 1)
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var ink: Color {
        if isFocused { return MidnightPalette.selectedInk }
        return isSelected ? MidnightPalette.fieldInk : MidnightPalette.ink
    }
}
#endif
